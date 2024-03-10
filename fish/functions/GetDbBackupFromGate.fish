function GetDbBackupFromGate --wraps='set backup_date (date +"%d.%m-%H:%M") && ssh gate "cd /var/panel && make backup" && scp gate:/var/panel/panel/storage/files/backup.sql /home/arsolitt/projects/ProtesianHosting/dump_newPteroDatabase{$backup_date}.sql' --description 'alias GetDbBackupFromGate set backup_date (date +"%d.%m-%H:%M") && ssh gate "cd /var/panel && make backup" && scp gate:/var/panel/panel/storage/files/backup.sql /home/arsolitt/projects/ProtesianHosting/dump_newPteroDatabase{$backup_date}.sql'
  set backup_date (date +"%d.%m-%H:%M") && ssh gate "cd /var/panel && make backup" && scp gate:/var/panel/panel/storage/files/backup.sql /home/arsolitt/projects/ProtesianHosting/dump_newPteroDatabase{$backup_date}.sql $argv
        
end
