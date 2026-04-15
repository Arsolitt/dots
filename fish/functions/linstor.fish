function linstor --description 'alias linstor kubectl exec -n cozy-linstor deploy/linstor-controller -- linstor'
    kubectl exec -n cozy-linstor deploy/linstor-controller -- linstor $argv
end
