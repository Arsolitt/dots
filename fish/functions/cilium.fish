function cilium --wraps=cilium-cli --description 'alias cilium cilium-cli'
    cilium-cli $argv
end
