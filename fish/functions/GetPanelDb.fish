function GetPanelDb --wraps='set backup_date (date +"%d.%m-%H:%M") && ssh main "cd /var/panel && make backup" && scp main:/var/panel/panel/storage/files/backup.sql /home/arsolitt/projects/ProtesianHosting/dump_newPteroDatabase{$backup_date}.sql $argv' --description 'alias GetPanelDb set backup_date (date +"%d.%m-%H:%M") && ssh main "cd /var/panel && make backup" && scp main:/var/panel/panel/storage/files/backup.sql /home/arsolitt/projects/ProtesianHosting/dump_newPteroDatabase{$backup_date}.sql $argv'
  set backup_date (date +"%d.%m-%H:%M") && ssh main "cd /var/panel && make backup" && scp main:/var/panel/panel/storage/files/backup.sql /home/arsolitt/projects/ProtesianHosting/dump_newPteroDatabase{$backup_date}.sql $argv $argv
        
end
