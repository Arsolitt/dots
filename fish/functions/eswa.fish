function eswa
    set mime (wl-paste --list-types 2>/dev/null | grep -E '^image/' | head -1)
    
    if test -z "$mime"
        echo "Error: No image in clipboard" >&2
        return 1
    end
    
    wl-paste -t $mime | swappy -f -
end
