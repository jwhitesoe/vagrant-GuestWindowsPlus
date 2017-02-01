module VagrantPlugins
  module GuestWindows
    module Cap
      module ChangeHostName

        def self.change_host_name(machine, name)
          puts "Next try"
          change_host_name_and_wait(machine, name, machine.config.vm.graceful_halt_timeout)
        end

      end
    end
  end
end
