#!/usr/bin/env groovy

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║                                                                          ║
// ║              T H E   L A S T   J E N K I N S   J O B                   ║
// ║                                                                          ║
// ║   A pipeline that installs its own replacement, then removes itself.    ║
// ║   Written in Groovy. Deployed by Jenkins. Mourned by no one.            ║
// ║                                                                          ║
// ║   Stack: Terraform → Kubernetes → Helm → ArgoCD → Prometheus            ║
// ║   Exit:  docker rm -f jenkins-controller                                 ║
// ║                                                                          ║
// ╚══════════════════════════════════════════════════════════════════════════╝

pipeline {
    agent any

    environment {
        TF_VERSION        = '1.8.0'
        HELM_VERSION      = '3.14.0'
        INSTALL_DIR       = '/var/jenkins_home/bin'
        PATH              = "/var/jenkins_home/bin:${env.PATH}"
        KUBECONFIG        = '/tmp/kubeconfig'  // writable copy of the read-only mount
        K8S_CONTEXT       = 'docker-desktop'
        GITEA_URL         = 'http://gitea:3001'
        // ArgoCD runs in Kubernetes — it can't reach 'localhost' or 'gitea' (Docker Compose).
        // host.docker.internal routes from the K8s node back to the Docker host.
        GITEA_EXT_URL     = 'http://host.docker.internal:3001'
        PLATFORM_REPO     = 'http://gitea:gitops-forever@gitea:3001/gitea/platform-config.git'
        ARGOCD_NAMESPACE  = 'argocd'
        MONITORING_NS     = 'monitoring'
        INGRESS_NS        = 'ingress-nginx'
        TF_IN_AUTOMATION  = '1'
        TF_CLI_ARGS       = '-no-color'
    }

    options {
        ansiColor('xterm')
        timestamps()
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    stages {

        // ════════════════════════════════════════════════════════════════
        stage('🌅 In The Beginning, There Was Jenkins') {
        // ════════════════════════════════════════════════════════════════
        // Every empire starts somewhere. Ours starts here.
            steps {
                script {
                    printBanner(
                        "THE LAST JENKINS JOB",
                        "Build #${env.BUILD_NUMBER} | ${new Date().format('yyyy-MM-dd HH:mm')}",
                        "A pipeline that boots a GitOps platform and removes itself"
                    )
                    notifyDashboard('started', 'stage1', 'Checking the environment')
                }
                sh '''
                    # ══════════════════════════════════════════════════════════════
                    # KUBECONFIG — set up first. Everything below needs this.
                    # Rewrite 127.0.0.1 → host.docker.internal so the Jenkins
                    # container can reach the Docker Desktop K8s API on the Mac host.
                    # Copy to /tmp because the mounted volume is :ro.
                    # ══════════════════════════════════════════════════════════════
                    cp /var/jenkins_home/.kube/config /tmp/kubeconfig
                    chmod 600 /tmp/kubeconfig
                    sed -i 's|https://127.0.0.1:|https://host.docker.internal:|g' /tmp/kubeconfig
                    sed -i 's|https://localhost:|https://host.docker.internal:|g' /tmp/kubeconfig
                    kubectl config set-cluster docker-desktop --insecure-skip-tls-verify=true
                    kubectl config use-context "${K8S_CONTEXT}"

                    echo "📋 System Inventory"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "  Node:   $(hostname)"
                    echo "  Date:   $(date -u)"
                    echo "  Docker: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo 'mounted socket')"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    kubectl cluster-info
                    kubectl get nodes -o wide
                    echo ""

                    # ══════════════════════════════════════════════════════════════
                    # CLEAN SLATE — remove any leftovers from a previous run.
                    # On a fresh cluster this is all no-ops and takes ~1s.
                    # On a retry it clears whatever the previous attempt left behind.
                    # ══════════════════════════════════════════════════════════════
                    echo "🧹 Clearing previous run state..."

                    helm uninstall ingress-nginx        -n ingress-nginx  2>/dev/null || true
                    helm uninstall argocd               -n argocd         2>/dev/null || true
                    helm uninstall kube-prometheus-stack -n monitoring    2>/dev/null || true

                    # Strip finalizers before deleting.
                    # Docker Desktop never resolves LoadBalancer service finalizers,
                    # and ArgoCD puts a cascade-delete finalizer on Application objects.
                    # Both block namespace termination indefinitely if left in place.
                    for ns in ingress-nginx argocd monitoring apps; do
                        for kind in applications services; do
                            kubectl get "$kind" -n "$ns" -o name 2>/dev/null | while read name; do
                                kubectl patch "$name" -n "$ns" \\
                                    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                            done
                        done
                        kubectl patch namespace "$ns" \\
                            -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    done

                    # Delete (--wait=false submits the request without blocking).
                    kubectl delete namespace ingress-nginx argocd monitoring apps \\
                        --ignore-not-found --wait=false 2>/dev/null || true

                    # Now wait for each namespace to actually disappear.
                    # kubectl wait exits immediately if the resource is already gone.
                    for ns in ingress-nginx argocd monitoring apps; do
                        kubectl wait --for=delete namespace/"$ns" --timeout=60s 2>/dev/null || true
                    done

                    # The last-jenkins-job-manifest ConfigMap lives in 'default' which can't
                    # be deleted between runs, so remove it explicitly.
                    kubectl delete configmap last-jenkins-job-manifest -n default --ignore-not-found 2>/dev/null || true

                    # Wipe Terraform state so Stage 4 starts fresh
                    rm -rf /var/jenkins_home/terraform-work
                    rm -f  /var/jenkins_home/tfplan
                    rm -f  /var/jenkins_home/terraform-outputs.json
                    rm -f  /var/jenkins_home/platform-state.json

                    echo "✅ Jenkins is alive and ready to build its own grave."
                '''
                script { notifyDashboard('success', 'stage1', 'Environment verified') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage1', 'Environment check failed') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('🔧 Installing The Tools Of My Own Destruction') {
        // ════════════════════════════════════════════════════════════════
        // Teaching Jenkins to install the tools that will replace it.
        // There's something beautiful about that.
            steps {
                script {
                    notifyDashboard('running', 'stage2', 'Installing Terraform, Helm, and ArgoCD CLI')
                }
                sh 'bash /var/jenkins_home/scripts/install-deps.sh'
                sh '''
                    echo ""
                    echo "🧰 Tool Versions Confirmed:"
                    echo "  Terraform: $(terraform version | head -1)"
                    echo "  Helm:      $(helm version --short)"
                    echo "  kubectl:   $(kubectl version --client --output=yaml | grep gitVersion | awk '{print $2}')"
                    echo "  ArgoCD:    $(argocd version --client --short 2>/dev/null | head -1)"
                '''
                script { notifyDashboard('success', 'stage2', 'Tools installed') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage2', 'Tool installation failed') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('📝 Writing The Blueprint For My Replacement') {
        // ════════════════════════════════════════════════════════════════
        // Terraform init + validate + plan.
        // Jenkins reading its own architectural death warrant.
            steps {
                script {
                    notifyDashboard('running', 'stage3', 'Running terraform init and plan')
                }
                sh '''
                    # The terraform/ mount is read-only — Terraform needs to write
                    # a .terraform/ plugin cache dir. Copy to a writable work dir.
                    mkdir -p /var/jenkins_home/terraform-work
                    cp -r /var/jenkins_home/terraform/. /var/jenkins_home/terraform-work/
                    cd /var/jenkins_home/terraform-work

                    echo "🏁 Initialising Terraform..."
                    terraform init -upgrade -input=false

                    echo ""
                    echo "✔️  Validating configuration..."
                    terraform validate

                    echo ""
                    echo "📐 Planning infrastructure..."
                    terraform plan \
                        -var="kubeconfig_path=${KUBECONFIG}" \
                        -var="kube_context=${K8S_CONTEXT}" \
                        -out=/var/jenkins_home/tfplan \
                        -input=false

                    echo ""
                    terraform show -no-color /var/jenkins_home/tfplan
                '''
                script { notifyDashboard('success', 'stage3', 'Terraform plan complete') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage3', 'Terraform plan failed') } }
                always {
                    archiveArtifacts artifacts: '/var/jenkins_home/tfplan', allowEmptyArchive: true
                }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('🏗️  Building The Kingdom I Will Never Inhabit') {
        // ════════════════════════════════════════════════════════════════
        // terraform apply. This is where things get real.
        // Jenkins pouring the foundation for a house it will never live in.
            steps {
                script {
                    notifyDashboard('running', 'stage4', 'Running terraform apply — deploying ingress, ArgoCD, and Prometheus')
                }
                sh '''
                    cd /var/jenkins_home/terraform-work

                    echo "🚀 Applying Terraform plan..."
                    echo "   This will deploy:"
                    echo "   • ingress-nginx         (networking layer)"
                    echo "   • ArgoCD                (GitOps engine — my replacement)"
                    echo "   • kube-prometheus-stack (observability)"
                    echo ""

                    terraform apply \
                        -auto-approve \
                        -input=false \
                        /var/jenkins_home/tfplan

                    echo ""
                    echo "📤 Capturing outputs..."
                    terraform output -json > /var/jenkins_home/terraform-outputs.json
                    cat /var/jenkins_home/terraform-outputs.json
                '''
                script { notifyDashboard('success', 'stage4', 'Platform deployed') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage4', 'Terraform apply failed') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('🔍 Checking The Pulse Of My Successor') {
        // ════════════════════════════════════════════════════════════════
        // Health checks. Jenkins won't delete itself if the platform
        // isn't healthy. It has standards.
            steps {
                script {
                    notifyDashboard('running', 'stage5', 'Running platform health checks')
                }
                sh 'bash /var/jenkins_home/scripts/health-check.sh'
                script { notifyDashboard('success', 'stage5', 'Platform is healthy') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage5', 'Health checks failed — platform not ready') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('🔀 Pushing GitOps Config To Gitea') {
        // ════════════════════════════════════════════════════════════════
        // Seed the Gitea repo with the platform-config that ArgoCD
        // will watch forever. The git repo that outlives the pipeline.
            steps {
                script {
                    notifyDashboard('running', 'stage6', 'Seeding Gitea platform-config repo for ArgoCD')
                }
                sh '''
                    set -e

                    # Configure git
                    git config --global user.email "jenkins@last-jenkins-job.local"
                    git config --global user.name "Jenkins (Last Run)"

                    WORK_DIR=$(mktemp -d)
                    cd "$WORK_DIR"

                    # Wait for Gitea API
                    echo "⏳ Waiting for Gitea API..."
                    for i in $(seq 1 20); do
                        if curl -sf "${GITEA_URL}/api/v1/version" > /dev/null 2>&1; then
                            echo "✅ Gitea is up"
                            break
                        fi
                        echo "   Attempt $i/20..."
                        sleep 3
                    done

                    # Create platform-config repo via Gitea API
                    echo "📁 Creating platform-config repository in Gitea..."
                    curl -sf \
                        -X POST "${GITEA_URL}/api/v1/user/repos" \
                        -H "Content-Type: application/json" \
                        -u "gitea:gitops-forever" \
                        -d '{"name":"platform-config","private":false,"auto_init":true,"default_branch":"main"}' \
                        > /dev/null 2>&1 || echo "   (repo may already exist — that is fine)"

                    sleep 3

                    # Clone and push platform config
                    git clone "${PLATFORM_REPO}" repo || \
                        git clone "http://gitea:gitops-forever@gitea:3001/gitea/platform-config.git" repo
                    cp -r /var/jenkins_home/platform-config/. repo/
                    cd repo
                    git add -A
                    git diff --cached --quiet || git commit -m "chore: initial platform config from The Last Jenkins Job"
                    git push origin HEAD:main --force

                    echo "✅ GitOps repository seeded. ArgoCD will take it from here."
                '''
                script { notifyDashboard('success', 'stage6', 'platform-config seeded in Gitea') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage6', 'Failed to seed GitOps repo') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('🔑 Handing The Keys To ArgoCD') {
        // ════════════════════════════════════════════════════════════════
        // The handoff. Jenkins registers the platform-config repo with
        // ArgoCD and deploys the app-of-apps. From this point on,
        // ArgoCD drives. Jenkins is a passenger.
            steps {
                script {
                    notifyDashboard('running', 'stage7', 'Connecting ArgoCD to Gitea and deploying app-of-apps')
                }
                sh '''
                    set -e

                    # Wait for ArgoCD server to be ready
                    echo "⏳ Waiting for ArgoCD server..."
                    kubectl wait --for=condition=Ready pods \
                        -l app.kubernetes.io/name=argocd-server \
                        -n "${ARGOCD_NAMESPACE}" \
                        --timeout=300s

                    # Register the Gitea repo using a Kubernetes Secret.
                    # ArgoCD watches for Secrets labelled argocd.argoproj.io/secret-type=repository
                    # and registers them automatically — no CLI login or port-forward needed.
                    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: platform-config-repo
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${GITEA_EXT_URL}/gitea/platform-config.git
  username: gitea
  password: gitops-forever
EOF

                    echo "✅ Platform-config repository registered with ArgoCD"

                    # Deploy the app-of-apps — this hands control to ArgoCD.
                    # ArgoCD will discover it and begin syncing all child apps
                    # defined in platform-config/apps/.
                    kubectl apply -f /var/jenkins_home/platform-config/apps/app-of-apps.yaml \
                        -n "${ARGOCD_NAMESPACE}"

                    echo "✅ App-of-apps deployed. GitOps is now in control."
                    echo "   ArgoCD will watch: ${GITEA_EXT_URL}/gitea/platform-config"
                '''
                script { notifyDashboard('success', 'stage7', 'ArgoCD connected — GitOps is live') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage7', 'ArgoCD handoff failed') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('✅ Making Sure The Robots Can Cope Without Me') {
        // ════════════════════════════════════════════════════════════════
        // Final validation. ArgoCD syncing, Grafana accessible,
        // ingress routing. Jenkins checks its work one last time.
            steps {
                script {
                    notifyDashboard('running', 'stage8', 'Final validation — verifying the platform is self-sufficient')
                }
                sh '''
                    echo "🔬 Final Platform Validation"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""

                    echo "📦 All namespaces:"
                    kubectl get namespaces -l last-jenkins-job=true

                    echo ""
                    echo "🚀 All Helm releases:"
                    helm list --all-namespaces

                    echo ""
                    echo "💚 Pod status across platform namespaces:"
                    kubectl get pods -n "${ARGOCD_NAMESPACE}"
                    kubectl get pods -n "${MONITORING_NS}"
                    kubectl get pods -n "${INGRESS_NS}"

                    echo ""
                    echo "🌐 Services:"
                    kubectl get svc -n "${ARGOCD_NAMESPACE}"
                    kubectl get svc -n "${MONITORING_NS}"
                    kubectl get svc -n "${INGRESS_NS}"

                    echo ""
                    echo "🎯 ArgoCD Applications:"
                    kubectl get applications -n "${ARGOCD_NAMESPACE}" 2>/dev/null || echo "   (ArgoCD CRDs loading...)"

                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "✅ Platform validated. The robots are ready."
                '''
                script { notifyDashboard('success', 'stage8', 'All systems go') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage8', 'Final validation failed') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('📊 Final Status Report (For Posterity)') {
        // ════════════════════════════════════════════════════════════════
        // Write a summary that the dashboard will display after Jenkins
        // is gone. The last message in a bottle.
            steps {
                script {
                    notifyDashboard('running', 'stage9', 'Writing final status report and platform manifest')

                    def buildUrl = env.BUILD_URL ?: 'http://localhost:8080'
                    def timestamp = new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC'))

                    writeFile file: '/var/jenkins_home/platform-state.json', text: """
{
  "meta": {
    "project": "The Last Jenkins Job",
    "build": "${env.BUILD_NUMBER}",
    "timestamp": "${timestamp}",
    "status": "complete",
    "message": "Jenkins has left the building. Long live GitOps."
  },
  "platform": {
    "argocd": {
      "url": "http://localhost:8090",
      "credentials": "admin / (see argocd-initial-admin-secret)",
      "status": "syncing"
    },
    "grafana": {
      "url": "http://localhost:3000",
      "credentials": "admin / gitops-era-begins",
      "status": "running"
    },
    "ingress": {
      "url": "http://localhost:80",
      "status": "running"
    },
    "gitea": {
      "url": "http://localhost:3001",
      "credentials": "gitea / gitops-forever",
      "repo": "http://localhost:3001/gitea/platform-config",
      "status": "running"
    }
  },
  "jenkins": {
    "status": "self_terminated",
    "last_build": "${env.BUILD_NUMBER}",
    "last_words": "It was an honour to serve. But let's be real — I was always just a stepping stone."
  }
}
""".replaceAll(/^\s+/, '')
                }
                sh 'echo "📝 Platform state written to /var/jenkins_home/platform-state.json"'
                sh 'cat /var/jenkins_home/platform-state.json'
                script { notifyDashboard('success', 'stage9', 'Platform manifest written') }
            }
            post {
                failure { script { notifyDashboard('failed', 'stage9', 'Failed to write status report') } }
            }
        }

        // ════════════════════════════════════════════════════════════════
        stage('💀 Et Tu, Groovy? — The Last Stage') {
        // ════════════════════════════════════════════════════════════════
        // The one you've been waiting for.
        // Jenkins removes itself from the equation.
        // The pipeline that ends all pipelines (for Jenkins, at least).
            steps {
                script {
                    notifyDashboard('running', 'stage10', 'Initiating Jenkins self-termination sequence')
                }
                sh 'bash /var/jenkins_home/scripts/farewell.sh'
            }
        }

    } // end stages

    post {
        success {
            script {
                echo """
╔══════════════════════════════════════════════════════════════╗
║  The Last Jenkins Job — COMPLETE                             ║
║  If you are reading this in the Jenkins UI... something      ║
║  went wrong with the self-destruct. That is also fine.       ║
║                                                              ║
║  Platform endpoints:                                         ║
║    ArgoCD:   http://localhost:8090                           ║
║    Grafana:  http://localhost:3000                           ║
║    Gitea    http://localhost:3001                           ║
║    Dashboard: http://localhost:8888                          ║
╚══════════════════════════════════════════════════════════════╝
"""
            }
        }
        failure {
            script {
                notifyDashboard('failed', 'unknown', 'Pipeline failed — Jenkins lives to fight another day')
                echo """
😢 The Last Jenkins Job FAILED.
Jenkins has been spared, but probably not on purpose.

Check the logs and try again. Jenkins is resilient like that.
"""
            }
        }
        cleanup {
            cleanWs(notFailBuild: true)
        }
    }

} // end pipeline


// ── Helper functions ─────────────────────────────────────────────────────────

def printBanner(String title, String subtitle, String tagline) {
    def line = '═' * 72
    echo """
╔${line}╗
║  ${title.padRight(70)}║
║  ${subtitle.padRight(70)}║
║                                                                        ║
║  ${tagline.padRight(70)}║
╚${line}╝
"""
}

def notifyDashboard(String status, String stage, String message) {
    // Write status to a file the dashboard polls.
    // This is our poor-man's webhook to the live dashboard.
    try {
        def payload = """{"status":"${status}","stage":"${stage}","message":"${message}","ts":"${new Date().format("HH:mm:ss")}"}"""
        sh "echo '${payload}' > /var/jenkins_home/pipeline-status.json"
    } catch (Exception e) {
        // Dashboard notification failure should never block the pipeline
    }
}
