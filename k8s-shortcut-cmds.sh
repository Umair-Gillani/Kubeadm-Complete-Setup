# ============================================================
# KUBECTL SHORTCUTS CHEAT SHEET
# Based on your .bashrc aliases and functions
# ============================================================



nano ~/.bashrc


# ============================================================
# KUBECTL SHORTCUTS - .bashrc
# ============================================================

# Enable aliases in interactive shell
shopt -s expand_aliases

# ============================================================
# 1. CORE COMMAND
# ============================================================

alias k='kubectl'

# ============================================================
# 2. FAST GET COMMANDS
# ============================================================

alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgpw='kubectl get pods -w'
alias kgpwa='kubectl get pods -A -w'

alias kgd='kubectl get deploy'
alias kgds='kubectl get daemonset'
alias kgss='kubectl get statefulset'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'
alias kgn='kubectl get nodes'
alias kgnw='kubectl get nodes -o wide'
alias kgns='kubectl get ns'
alias kgcm='kubectl get configmap'
alias kgsec='kubectl get secret'
alias kgsa='kubectl get serviceaccount'
alias kgj='kubectl get jobs'
alias kgcj='kubectl get cronjobs'
alias kgpvc='kubectl get pvc'
alias kgpv='kubectl get pv'
alias kgrs='kubectl get rs'
alias kgep='kubectl get endpoints'
alias kgaa='kubectl get all -A'
alias kga='kubectl get all'

alias kge='kubectl get events --sort-by=.metadata.creationTimestamp'
alias kgea='kubectl get events -A --sort-by=.metadata.creationTimestamp'

# ============================================================
# 3. OUTPUT HELPER VARIABLES
# Usage:
# k get pod mypod $ky
# kgp $kA
# kgp $kw
# ============================================================

ky='-o yaml'
kj='-o json'
kw='--watch'
kA='-A'

# ============================================================
# 4. DESCRIBE / EDIT / DELETE / APPLY
# ============================================================

alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kdd='kubectl describe deploy'
alias kds='kubectl describe svc'
alias kdn='kubectl describe node'

alias ke='kubectl edit'
alias kep='kubectl edit pod'
alias ked='kubectl edit deploy'
alias kes='kubectl edit svc'
alias kecm='kubectl edit configmap'

alias kdel='kubectl delete'
alias kdelp='kubectl delete pod'
alias kdeld='kubectl delete deploy'
alias kdels='kubectl delete svc'
alias kdelns='kubectl delete ns'

alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias krf='kubectl replace -f'

# ============================================================
# 5. ROLLOUT / RESTART / SCALE
# ============================================================

alias krs='kubectl rollout status'
alias kru='kubectl rollout undo'
alias krh='kubectl rollout history'
alias krr='kubectl rollout restart'

alias ksd='kubectl scale deploy'
alias ksss='kubectl scale statefulset'

# ============================================================
# 6. LOGS / EXEC / DEBUGGING
# ============================================================

alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias klp='kubectl logs --previous'
alias kpf='kubectl port-forward'
alias katt='kubectl attach -it'

# ============================================================
# 7. CONTEXT / NAMESPACE SHORTCUTS
# ============================================================

alias kctx='kubectl config current-context'
alias kctxs='kubectl config get-contexts'
alias kuse='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

# ============================================================
# 8. METRICS / API / HELP
# ============================================================

alias ktopn='kubectl top nodes'
alias ktopp='kubectl top pods'
alias ktoppa='kubectl top pods -A'
alias kapi='kubectl api-resources'
alias kapiv='kubectl api-versions'
alias kexp='kubectl explain'

# ============================================================
# 9. DRY RUN / DIFF
# ============================================================

alias kdry='kubectl apply --dry-run=client -f'
alias kdiff='kubectl diff -f'

# ============================================================
# 10. HANDY FUNCTIONS
# ============================================================

# Switch namespace quickly
kn() {
  if [ -z "$1" ]; then
    echo "Usage: kn <namespace>"
    return 1
  fi

  kubectl config set-context --current --namespace="$1"
}

# Get all resources in a namespace
kall() {
  local ns="${1:-default}"
  kubectl get all -n "$ns"
}

# Get pods in a namespace with wide output
kgpn() {
  local ns="${1:-default}"
  kubectl get pods -n "$ns" -o wide
}

# Open sh shell inside pod/container
ksh() {
  if [ -z "$1" ]; then
    echo "Usage: ksh <pod> -n <namespace> [-c container]"
    return 1
  fi

  kubectl exec -it "$@" -- sh
}

# Open bash shell inside pod/container
kbash() {
  if [ -z "$1" ]; then
    echo "Usage: kbash <pod> -n <namespace> [-c container]"
    return 1
  fi

  kubectl exec -it "$@" -- bash
}

# Follow logs in a namespace
klfn() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: klfn <pod> <namespace> [extra log args]"
    echo "Example: klfn mypod prod -c app"
    return 1
  fi

  local pod="$1"
  local ns="$2"
  shift 2

  kubectl logs -f "$pod" -n "$ns" "$@"
}

# Describe pod in a namespace
kdpn() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: kdpn <pod> <namespace>"
    return 1
  fi

  kubectl describe pod "$1" -n "$2"
}

# Restart deployment in a namespace
krrn() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: krrn <deployment> <namespace>"
    return 1
  fi

  kubectl rollout restart deploy/"$1" -n "$2"
}

# Grep pods across all namespaces
kgpg() {
  if [ -z "$1" ]; then
    echo "Usage: kgpg <keyword>"
    return 1
  fi

  kubectl get pods -A | grep -i "$1"
}

# Show all pod images across all namespaces
kimages() {
  kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
    | column -t
}

# Show pod IPs across all namespaces
kpodips() {
  kubectl get pods -A -o wide
}

# Force delete pod immediately
kdelpf() {
  if [ -z "$1" ]; then
    echo "Usage: kdelpf <pod> [-n namespace]"
    return 1
  fi

  kubectl delete pod "$@" --grace-period=0 --force
}

# Watch any resource live
kgw() {
  if [ -z "$1" ]; then
    echo "Usage: kgw <resource> [name] [flags]"
    echo "Example: kgw pods -n default"
    echo "Example: kgw deploy -A"
    return 1
  fi

  kubectl get "$@" --watch
}

# ============================================================
# 11. KUBECTL AUTOCOMPLETION
# ============================================================

if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash) 2>/dev/null || true
  complete -o default -F __start_kubectl k 2>/dev/null || true
fi

# ============================================================
# END OF KUBECTL SHORTCUTS
# ============================================================


source ~/.bashrc



# ======================================================================================================================================================================
# ======================================================================================================================================================================
# ======================================================================================================================================================================




# ============================================================
# 1. CORE COMMAND
# ============================================================

# Main kubectl shortcut
k                         # Runs kubectl

# Example:
# k get pods


# ============================================================
# 2. FAST GET COMMANDS
# ============================================================

kg                        # kubectl get
kgp                       # kubectl get pods
kgpa                      # kubectl get pods -A               -> get pods in all namespaces
kgpw                      # kubectl get pods -w               -> watch pods live
kgpwa                     # kubectl get pods -A -w            -> watch all pods in all namespaces

kgd                       # kubectl get deploy                -> get deployments
kgds                      # kubectl get daemonset             -> get daemonsets
kgss                      # kubectl get statefulset           -> get statefulsets
kgs                       # kubectl get svc                   -> get services
kgi                       # kubectl get ingress               -> get ingress resources
kgn                       # kubectl get nodes                 -> get cluster nodes
kgnw                      # kubectl get nodes -o wide         -> nodes with extra details
kgns                      # kubectl get ns                    -> get namespaces
kgcm                      # kubectl get configmap             -> get configmaps
kgsec                     # kubectl get secret                -> get secrets
kgsa                      # kubectl get serviceaccount        -> get service accounts
kgj                       # kubectl get jobs                  -> get jobs
kgcj                      # kubectl get cronjobs              -> get cronjobs
kgpvc                     # kubectl get pvc                   -> get persistent volume claims
kgpv                      # kubectl get pv                    -> get persistent volumes
kgrs                      # kubectl get rs                    -> get replica sets
kgep                      # kubectl get endpoints             -> get endpoints
kgaa                      # kubectl get all -A                -> get all resources in all namespaces
kga                       # kubectl get all                   -> get all resources in current namespace
kge                       # kubectl get events --sort-by=.metadata.creationTimestamp
                          # show events sorted by time
kgea                      # kubectl get events -A --sort-by=.metadata.creationTimestamp
                          # show all events across namespaces sorted by time


# ============================================================
# 3. OUTPUT HELPERS
# ============================================================

# These are helper flags used with commands
$ky                       # -o yaml                          -> output in YAML
$kj                       # -o json                          -> output in JSON
$kw                       # --watch                          -> watch changes live
$kA                       # -A                               -> all namespaces

# Examples:
# k get pod mypod $ky
# kgp $kA
# kgp $kw


# ============================================================
# 4. DESCRIBE / EDIT / DELETE / APPLY
# ============================================================

# Describe resources
kd                        # kubectl describe
kdp                       # kubectl describe pod
kdd                       # kubectl describe deploy
kds                       # kubectl describe svc
kdn                       # kubectl describe node

# Edit resources
ke                        # kubectl edit
kep                       # kubectl edit pod
ked                       # kubectl edit deploy
kes                       # kubectl edit svc
# NOTE: alias "కెcm" seems malformed / typo
# Correct version should probably be:
# alias కెcm='k edit configmap'
# Better to rename it to:
# alias kecm='k edit configmap'

# Delete resources
kdel                      # kubectl delete
kdelp                     # kubectl delete pod
kdeld                     # kubectl delete deploy
kdels                     # kubectl delete svc
kdelns                    # kubectl delete ns

# Apply / replace resource files
kaf                       # kubectl apply -f
kdf                       # kubectl delete -f
krf                       # kubectl replace -f


# ============================================================
# 5. ROLLOUT / RESTART / SCALE
# ============================================================

krs                       # kubectl rollout status           -> check rollout status
kru                       # kubectl rollout undo             -> rollback to previous version
krh                       # kubectl rollout history          -> show rollout history
krr                       # kubectl rollout restart          -> restart deployment/stateful app rollout

ksd                       # kubectl scale deploy             -> scale deployment
ksss                      # kubectl scale statefulset        -> scale statefulset


# ============================================================
# 6. LOGS / EXEC / DEBUGGING
# ============================================================

kl                        # kubectl logs                     -> view logs
klf                       # kubectl logs -f                  -> follow logs live
klp                       # kubectl logs --previous          -> show previous container logs
kpf                       # kubectl port-forward             -> port forward local to pod/service
katt                      # kubectl attach -it               -> attach interactive terminal to container


# ============================================================
# 7. EXEC HELPERS
# ============================================================

# Open shell inside container/pod using sh
ksh <pod> -n <namespace>                  # kubectl exec -it <pod> -n <namespace> -- sh

# Open shell inside container/pod using bash
kbash <pod> -n <namespace>                # kubectl exec -it <pod> -n <namespace> -- bash

# Example:
# ksh my-pod -n myns
# kbash my-pod -c app -n myns


# ============================================================
# 8. CONTEXT / NAMESPACE SHORTCUTS
# ============================================================

kctx                      # kubectl config current-context   -> show current context
kctxs                     # kubectl config get-contexts      -> list all contexts
kuse <context-name>       # kubectl config use-context       -> switch cluster context
kns <namespace>           # kubectl config set-context --current --namespace
                          # set current namespace

# Examples:
# kns my-namespace
# kuse prod-cluster


# ============================================================
# 9. METRICS / API / HELP
# ============================================================

ktopn                     # kubectl top nodes                -> CPU/memory usage of nodes
ktopp                     # kubectl top pods                 -> CPU/memory usage of pods
ktoppa                    # kubectl top pods -A              -> pod metrics in all namespaces
kapi                      # kubectl api-resources            -> list all kubernetes resource types
kapiv                     # kubectl api-versions             -> list supported API versions
kexp <resource>           # kubectl explain                  -> explain resource fields


# ============================================================
# 10. DRY RUN / DIFF
# ============================================================

kdry                      # kubectl apply --dry-run=client -f
                          # validate manifest locally without applying

kdiff                     # kubectl diff -f
                          # compare local manifest with cluster state


# ============================================================
# 11. HANDY FUNCTIONS
# ============================================================

# Switch namespace quickly
kn <namespace>
# Example:
# kn dev
# Effect:
# kubectl config set-context --current --namespace=dev


# Get all resources in a namespace
kall <namespace>
# Example:
# kall kube-system
# Default namespace is "default" if not provided


# Get pods in a namespace with wide output
kgpn <namespace>
# Example:
# kgpn default
# Shows pod IP, node, and more details


# Follow logs in a namespace
klfn <pod> <namespace> [extra kubectl log args]
# Example:
# klfn mypod prod
# klfn mypod prod -c app


# Describe pod in a namespace
kdpn <pod> <namespace>
# Example:
# kdpn mypod default


# Restart deployment in a namespace
krrn <deployment> <namespace>
# Example:
# krrn nginx-deployment default


# Grep pods across all namespaces
kgpg <keyword>
# Example:
# kgpg nginx
# Finds pods matching text


# Show all pod images across all namespaces
kimages
# Output:
# namespace   pod-name   image-name


# Show pod IPs across all namespaces
kpodips
# Same as:
# kubectl get pods -A -o wide


# Force delete pod immediately
kdelpf <pod>
# Example:
# kdelpf mypod
# Deletes pod with no graceful shutdown


# Watch any resource live
kgw <resource> [name] [flags]
# Example:
# kgw pods -n default
# kgw deploy -A


# ============================================================
# 12. COMMON REAL-WORLD USAGE EXAMPLES
# ============================================================

# View all pods in all namespaces
kgpa

# Watch pods live
kgpw

# Check node details
kgnw

# Describe a failing pod
kdp mypod -n default

# Follow logs of a pod
klf mypod -n default

# Enter pod shell
ksh mypod -n default

# Restart deployment
krr deploy/myapp -n default

# Restart deployment using helper function
krrn myapp default

# Apply manifest
kaf deployment.yaml

# Validate manifest without applying
kdry deployment.yaml

# Diff manifest against cluster
kdiff deployment.yaml

# Switch namespace
kn dev

# Show all resources in namespace
kall dev

# Show latest cluster events
kge

# Show images used by all pods
kimages

