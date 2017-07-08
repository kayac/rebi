module Rebi
  class ZipHelper

    def initialize
      `git status`
      raise Rebi::Error::NoGit.new("Not a git repository") unless $?.success?
    end

    def ls_files
      `git ls-files`.split("\n")
    end

    def raw_zip_archive opts={}
      tmp_file = Tempfile.new("git_archive")
      system "git archive --format=zip HEAD > #{tmp_file.path}"
      return tmp_file
    end

    def version_label
      `git describe --always --abbrev=8`.chomp
    end

    def message
      `git log --oneline -1`.chomp.split(" ")[1..-1].join(" ")[0..190]
    end

    # Create zip archivement
    def gen env_conf
      Rebi.log("Creating zip archivement", env_conf.name)
      start = Time.now
      ebextensions = env_conf.ebextensions
      files = ls_files
      tmp_file = raw_zip_archive
      tmp_folder = Dir.mktmpdir
      Zip::File.open(tmp_file) do |z|
        ebextensions.each do |ex_folder|
          Dir.glob("#{ex_folder}/*.config") do |fname|
            next unless (File.file?(fname) && files.include?(fname))
            next unless y = YAML::load(ErbHelper.new(File.read(fname), env_conf.environment_variables).result)
            basename = File.basename(fname)
            target = ".ebextensions/#{basename}"
            tmp_yaml = "#{tmp_folder}/#{basename}"
            File.open(tmp_yaml, 'w') do |f|
              f.write y.to_yaml
            end
            z.remove target if z.find_entry target
            z.add target, tmp_yaml
          end
        end
      end
      FileUtils.rm_rf tmp_folder
      Rebi.log("Zip was created in: #{Time.now - start}s", env_conf.name)
      return {
        label: Time.now.strftime("app_#{env_conf.name}_#{version_label}_%Y%m%d_%H%M%S"),
        file: File.open(tmp_file.path),
        message: message,
      }
    end

  end
end
