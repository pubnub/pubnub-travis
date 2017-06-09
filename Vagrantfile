
# Vagrantfile for Travis Enterprise

unless Vagrant.has_plugin? "vagrant-triggers"
    raise "Required plugin 'vagrant-triggers' not installed"
end

Vagrant.configure("2") do |config|

    config.vm.define "platform" do |platform|
        platform.vm.box = "travis-platform"
        platform.vm.hostname = "travis-platform"
        platform.ssh.keep_alive = true

        platform_ip = "192.168.33.90"

        platform.vm.network "private_network", ip: platform_ip

        platform.vm.provider "virtualbox" do |vb|
            vb.name = "travis-platform"
            vb.memory = "6144"
            vb.cpus = 4
        end

        platform.vm.synced_folder ".", "/vagrant", disabled: true

        # Render templates
        platform.trigger.before :up do
            run "scripts/render_templates.sh"
        end

        # Upload required files to /tmp
        platform.vm.provision "file", source: "certs", destination: "/tmp/certs"
        platform.vm.provision "file", source: "rendered", destination: "/tmp/rendered"

        # Move required files to correct location
        platform.vm.provision "shell", inline: "mv /tmp/certs /opt/pubnub"
        platform.vm.provision "shell", inline: "mv /tmp/rendered/replicated.conf /etc"
        platform.vm.provision "shell", inline: "mv /tmp/rendered/settings.json /opt/pubnub/travis-platform"

        # Run installation
        platform_install_args = "no-proxy private-address=#{platform_ip} public-address=#{platform_ip}"
        platform.vm.provision "shell", inline: "/opt/pubnub/travis-platform/installer.sh #{platform_install_args}"
    end
end
