
# Vagrantfile for Travis Enterprise

unless Vagrant.has_plugin? "vagrant-triggers"
    raise Vagrant::Errors::VagrantError.new, "Missing required plugin 'vagrant-triggers'"
end

LOCAL_CONFIG = YAML::load(File.open(File.join(File.expand_path(File.dirname(__FILE__)), "local_config.yml")))
PLATFORM_IP = LOCAL_CONFIG["vagrant_platform_ip"]
WORKER_COUNT = LOCAL_CONFIG["vagrant_worker_count"].to_i

Vagrant.configure("2") do |config|

    # Render templates
    config.trigger.before :up do
        run "scripts/render_templates.sh"
    end

    # Platform VM
    config.vm.define "travis-platform" do |platform|
        platform.vm.box = "travis-platform"
        platform.vm.hostname = "travis-platform"
        platform.ssh.keep_alive = true

        platform.vm.network "private_network", ip: PLATFORM_IP

        platform.vm.provider "virtualbox" do |vb|
            vb.name = "travis-platform"
            vb.memory = "6144"
            vb.cpus = 4
        end

        platform.vm.synced_folder ".", "/vagrant", disabled: true

        # Upload required files to /tmp
        platform.vm.provision "file", source: "certs", destination: "/tmp/certs"
        platform.vm.provision "file", source: "rendered/platform", destination: "/tmp/rendered"

        # Move required files to correct location
        platform.vm.provision "shell", inline: "mv /tmp/certs /opt/pubnub"
        platform.vm.provision "shell", inline: "mv /tmp/rendered/replicated.conf /etc"
        platform.vm.provision "shell", inline: "mv /tmp/rendered/settings.json /opt/pubnub/travis-platform"

        # Run installation
        platform_install_args = "no-proxy private-address=#{PLATFORM_IP} public-address=#{PLATFORM_IP}"
        platform.vm.provision "shell", inline: "/opt/pubnub/travis-platform/installer.sh #{platform_install_args}"
    end

    # Worker VM(s)
    (1..WORKER_COUNT).each do |worker_index|
        config.vm.define "travis-worker#{worker_index}" do |worker|
            worker.vm.box = "travis-worker"
            worker.vm.hostname = "travis-worker#{worker_index}"
            worker.ssh.keep_alive = true

            worker_ip = "192.168.33.#{90 + worker_index}"

            worker.vm.network "private_network", ip: worker_ip

            worker.vm.provider "virtualbox" do |vb|
                vb.name = "travis-worker#{worker_index}"
                vb.memory = "1024"
                vb.cpus = 4
            end

            worker.vm.synced_folder ".", "/vagrant", disabled: true

            # Add platform ip -> host mapping to /etc/hosts
            worker.vm.provision "shell", inline: "echo \'#{PLATFORM_IP} #{LOCAL_CONFIG["platform_fqdn"]}\' >> /etc/hosts"

            # Upload required files to /tmp
            worker.vm.provision "file", source: "rendered/worker", destination: "/tmp/rendered"

            # Move required files to correct location
            worker.vm.provision "shell", inline: "mv /tmp/rendered/travis-enterprise /etc/default"

            # Restart worker service with updated /etc/defaults
            worker.vm.provision "shell", inline: "restart travis-worker"
        end
    end
end
