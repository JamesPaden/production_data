def environment_info
  @environment_info ||= 
    begin
      run("cat #{current_path}/config/database.yml") do |channel, stream, data|
        @environment_info = YAML.load(data)[rails_env]
      end
      @environment_info
    end
end

task :dump_database_config_from_production_to_tmp do
  run("cat #{current_path}/config/database.yml") do |channel, stream, data|
    File.open(File.join("tmp", "production_db_config.yml"), "w") { |f| f.write data }
  end
end

def production_database
  environment_info["database"]
end

def production_dbhost
  environment_info["host"]
end

def dbuser
  environment_info["username"]
end

def dbpass
  environment_info["password"]
end

namespace :production_data do
  namespace :db do
    desc "Backup your MySQL database to shared_path+/db_backups with one insert on a line"
    task :dump_with_many_inserts, :roles => :db, :only => {:primary => true} do
      top.db.backup_name
      if environment_info['adapter'] == 'mysql'
        dbhost = environment_info['host']
        dbhost = environment_dbhost.sub('-master', '-replica') if dbhost != 'localhost' # added for Solo offering, which uses localhost
        run "mysqldump --skip-extended-insert --add-drop-table -u #{dbuser} -h #{dbhost} -p #{environment_database} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out |
          ch.send_data "#{dbpass}\n" if out=~ /^Enter password:/
        end
      else 
        puts "OMGZ not mysql"
      end
    end

    desc "Sync your production database to your local workstation"
    task :dump_to_local, :roles => :db, :only => {:primary => true} do
      top.db.backup_name
      dump_with_many_inserts
      filename = ENV['FILE'] || "tmp/#{File.basename(backup_file)}.bz2"
      get "#{backup_file}.bz2", filename # "/tmp/#{application}.sql.gz"
    end 

    desc "Upload db dump to server (requires FILE arg)"
    task :upload_db_dump, :roles => :db, :only => { :primary => true } do
      filename = ENV['FILE']
      upload filename, "#{current_path}/tmp/#{File.basename(filename)}"
    end

    desc "Import db dump on server (requires FILE arg)"
    task :remote_import_and_migrate, :roles => :db, :only => { :primary => true } do
      filename = ENV['FILE']
      run "cd #{current_path} && RAILS_ENV='#{rails_env}' rake import_production_data DB_BACKUP_FILE='#{filename}' --trace && RAILS_ENV='#{rails_env}' rake db:migrate --trace"
    end
    
    desc "Clone Production Database to Staging Database."
    task :clone_prod_to_staging_with_filtering, :roles => :db, :only => { :primary => true } do
      top.production
      top.db.backup_name
      filename = "tmp/#{File.basename(backup_file)}.bz2"

      system "cap production production_data:db:dump_to_local FILE='#{filename}'"

      system "cap staging production_data:db:upload_db_dump FILE='#{filename}'"

      system "cap staging production_data:db:remote_import_and_migrate FILE='#{filename}'"
    end
  end
end
