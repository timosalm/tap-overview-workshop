Tekton is a cloud-native solution for building CI/CD systems that runs as an extension on a Kubernetes cluster and comprises a set of **Kubernetes Custom Resources that define the building blocks** you can create and reuse for your pipelines. 

It consists of **Tekton Pipelines**, which provides the building blocks, and of supporting components, such as Tekton CLI, Tekton Triggers and Tekton Catalog, that make Tekton a complete ecosystem.

Only Tekton Pipelines will be installed as part of TAP. 

Both, OpenShift Piplines and Jenkins X are based on Tekton.

##### Concept model

A **Step** is an operation in a CI/CD workflow, such as running some unit tests for a Python web app, or the compilation of a Java program. Tekton performs each step with a container image you provide. 

Tekton introduces the concept of **Tasks** for simpler workloads such as running a test which executes in a single Kubernetes Pod and defines a series of ordered **Steps**. 
A **TaskRun** instantiates a specific Task to execute on a particular set of inputs and produce a particular set of outputs.

For more complex workloads, there is a concept of **Pipelines** that define a series of ordered Tasks, and just like Steps in a Task, a Task in a Pipeline can use the output of a previously executed Task as its input. 

![Pipeline Concept Diagram](../images/tekton.png)

Each Task and Pipeline may have its own inputs and outputs, known as input and output **resources** in Tekton. 
**PipelineResources** have been deprecated and to ease migration away from PipelineResources some types have an equivalent **default Task** available in the [catalog](https://github.com/tektoncd/catalog/tree/main/task) which have to be manually installed in a TAP environment.

A **PipelineRun** instantiates a specific Pipeline to execute on a particular set of inputs and produce a particular set of outputs to particular destinations.
Similarly, a **TaskRun** is a specific execution of a task.

![Pipeline Run Concept Diagram](../images/tekton-runs.png)

###### Automation of our path to production

To get familiar with Tekton Piplines, let's build a Tekton Pipeline to automate our path to production.
```terminal:execute
command: mkdir tekton-pipeline
```

```editor:append-lines-to-file
file: tekton-pipeline/pipeline.yaml
text: |2
  apiVersion: tekton.dev/v1beta1
  kind: Pipeline
  metadata:
    name: path-to-prod-pipeline
  spec:
    params:
    - name: git-url
      type: string
    - name: git-revision
      type: string
      default: main
    - name: app-name
      type: string
    - name: app-image-tag
      type: string
```

After we have defined a name and all input parameters for our pipeline, the next step is to define the different tasks. 

The first one is the **git-clone task**, which we can install via the following command in our namespace.
```terminal:execute
command: kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.5/git-clone.yaml
clear: true
```
We can now reference this task in our Pipeline with the following specification.
{% raw %}
```editor:append-lines-to-file
file: tekton-pipeline/pipeline.yaml
text: |2
    workspaces:
    - name: git-source
    tasks:
    - name: fetch-from-git
      taskRef:
        name: git-clone
      params:
      - name: url
        value: $(params.git-url)
      - name: revision
        value: $(params.git-revision)
      workspaces:
      - name: output
        workspace: git-source
```
{% endraw %}
In addition to the task reference and parameters, there is also a **Workspace** configuration used for the output - in this case the source code fetched from the git repository. Tasks specify where a Workspace resides on disk for its Steps. At runtime, a PipelineRun or TaskRun provides the specific details of the Volume that is mounted into that Workspace.

As next step of our path to production we want to run unit tests. For this, we first have to create our own custom Task ...
{% raw %}
```editor:append-lines-to-file
file: tekton-pipeline/test-task.yaml
text: |2
  apiVersion: tekton.dev/v1beta1
  kind: Task
  metadata:
    name: mvn-test
  spec:
    workspaces:
    - name: source
    steps:
    - name: test
      image: maven:3-openjdk-11
      script: |-
        mvn test -f \$(workspaces.source.path)/
```
{% endraw %}

... and reference it in the Pipeline specification.
{% raw %}
```editor:append-lines-to-file
file: tekton-pipeline/pipeline.yaml
text: |2
    - name: run-tests
      taskRef:
        name: mvn-test
      runAfter: 
      - fetch-from-git
      workspaces:
      - name: source
        workspace: git-source
```
{% endraw %}
After the unit tests ran successful, we want to **trigger VMware Tanzu Build Service to build and push an image** to our registry of choice which also has to be implemented as a custom Task.
{% raw %}
```editor:append-lines-to-file
file: tekton-pipeline/build-image-task.yaml
text: |2
  apiVersion: tekton.dev/v1beta1
  kind: Task
  metadata:
    name: tbs
  spec:
    params:
    - name: app-name
    - name: app-image-tag
    workspaces:
    - name: source
    results:
    - name: image-digest
      description: Digest of the image just built.
    steps:
    - name: build-and-push
      image: kpack/kp
      script: |-
        #!/bin/bash
        set -euxo pipefail

        current_namespace=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
        # Set contexts from local service account for kp-cli
        kubectl config set-cluster tbs-cluster --server=https://kubernetes.default \
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        kubectl config set-context tbs --cluster=tbs-cluster
        kubectl config set-credentials tbs-user \
            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
        kubectl config set-context tbs --user=tbs-user \
            --namespace="\${current_namespace}"
        kubectl config use-context tbs

        if kp image save \$(params.app-name) \
            --tag \$(params.app-image-tag) \
            --local-path \$(workspaces.source.path)/. \
            --namespace="\${current_namespace}" --wait >/dev/null; then
            echo "Image build and push finished successfull"
        else
            echo Image build and push finished with error code $?
        fi

        kubectl get images.kpack.io spring-sensors -o jsonpath='{.status.latestImage}' --namespace="\${current_namespace}" | tee /tekton/results/image-digest
        cat /tekton/results/image-digest 
```

After that, we are also able to reference it in our Pipeline.
{% raw %}
```editor:append-lines-to-file
file: tekton-pipeline/pipeline.yaml
text: |2
    - name: build-image
      taskRef:
        name: tbs
      runAfter: 
      - run-tests
      params:
      - name: app-name
        value: $(params.app-name)
      - name: app-image-tag
        value: $(params.app-image-tag)
      workspaces:
      - name: source
        workspace: git-source
```
{% endraw %}
The last step in our path to production is the **deployment via a Knative Serving Service**. For the kn CLI, there is also a **default Task** available which we can install via ...
```terminal:execute
command: kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/kn/0.1/kn.yaml
clear: true
```
... and reference in our Pipeline.
{% raw %}
```editor:append-lines-to-file
file: tekton-pipeline/pipeline.yaml
text: |2
    - name: deploy-application
      taskRef:
        name: kn
      runAfter: 
      - build-image
      params:
      - name: ARGS
        value:
        - 'service'
        - 'create'
        - '$(params.app-name)'
        - '--force'
        - '--image=$(tasks.build-image.results.image-digest)'
```
{% endraw %}
Now we have to define a **PipelineRun** that sets values for our parameters.
```terminal:execute
command:  |
    cat <<EOF> tekton-pipeline/pipeline-run.yaml
    apiVersion: tekton.dev/v1beta1
    kind: PipelineRun
    metadata:
      name: path-to-prod-pipeline-run
    spec:
      workspaces:
      - name: git-source
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
      pipelineRef:
        name: path-to-prod-pipeline
      params:
      - name: git-url
        value: https://github.com/tsalm-pivotal/spring-sensors.git
      - name: app-name
        value: spring-sensors
      - name: app-image-tag
        value: ${CONTAINER_REGISTRY_HOSTNAME}/tap-wkld/spring-sensors-tekton
    EOF
clear: true
```
```editor:open-file
file: tekton-pipeline/pipeline-run.yaml
line: 1
```

Let's apply all those custom resources to our cluster. Sometimes the PipelineRun fails because the Pipline is not yet available. This is why we apply our resources in an order.
```terminal:execute
command: ytt -f tekton-pipeline/build-image-task.yaml -f tekton-pipeline/test-task.yaml -f tekton-pipeline/pipeline.yaml -f tekton-pipeline/pipeline-run.yaml | kubectl apply -f-
clear: true
```

As an alternative to kubectl, we can use the tkn cli to discover our Pipeline, PipelineRuns and Tasks in the cluster.
```execute
tkn pipelinerun list
```
```execute
tkn pipelinerun describe path-to-prod-pipeline-run
```
```execute
tkn pipelinerun logs path-to-prod-pipeline-run -f
```

If the PipelineRun is successful, we can have a look at our tested and deployed application.
```terminal:execute
command: kn service list
clear: true
```

What's missing for our path to production is the piece that our Pipeline will be executed on every push to our GIT repository.
**Tekton Triggers** is a Tekton component that allows you to detect and extract information from events from a variety of sources and deterministically instantiate and execute TaskRuns and PipelineRuns based on that information.
Because Tekton Triggers are not installed via TAP, we will not cover it in this workshop.

Let’s clean up our resources before we move on.
```execute
rm -rf tekton-pipeline
ytt -f tekton-pipeline/build-image-task.yaml -f tekton-pipeline/test-task.yaml -f tekton-pipeline/pipeline.yaml -f tekton-pipeline/pipeline-run.yaml | kubectl delete -f-
```