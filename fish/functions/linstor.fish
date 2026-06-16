function linstor --description 'alias linstor kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor'
    kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor $argv
end
