require "vagrant/GuestWindowsPlus/version"

module VagrantPlugins
  module GuestWindowsPlus
    class Plugin < Vagrant.plugin("2")
      name "Windows guest plus"
      description "Better Windows guest support."

      guest(:windowsplus, :windows)  do
        init!
        Guest
      end

      guest_capability(:windowsplus, :change_host_name) do
        #require_relative "../windows/cap/change_host_name"
        Cap::ChangeHostName
      end

      def self.init!
        return if defined?(@_init)
        I18n.load_path << File.expand_path(
          "templates/locales/guest_windows.yml", Vagrant.source_root)
        I18n.reload!
        @_init = true
      end

    end
    class Guest < Vagrant.plugin("2", :guest)
      def detect?(machine)
        # See if the Windows directory is present.
        machine.communicate.test("test -d $Env:SystemRoot")
      end
    end
    module Cap
      module ChangeHostName

        def self.change_host_name(machine, name)
          arr = name.split('.', 2)
          hostname=arr[0]
          domain=arr[1]
          dmres = change_primary_dns_suffix(machine, domain)
          hnres = really_change_host_name(machine, hostname) 
          if dmres || hnres 
            reboot_and_wait(machine, machine.config.vm.graceful_halt_timeout)
          end
        end

        def self.reboot_and_wait(machine, sleep_timeout)
          # reboot host if rename succeeded
          script = <<-EOH
              shutdown /r /t 5 /f /d p:4:1 /c "Vagrant Rename Computer"
              exit 0
          EOH

          machine.communicate.execute(
            script,
            error_class: Errors::RenameComputerFailed,
            error_key: :rename_computer_failed)

          # Don't continue until the machine has shutdown and rebooted
          sleep(sleep_timeout)
        end

        def self.change_primary_dns_suffix(machine, suffix)
          return false if machine.communicate.test("if ([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName -eq '#{suffix}') { exit 0 } exit 1")
          script= <<EOH
function Set-PrimaryDnsSuffix {
  param ([string] $Suffix)  
  $ComputerNamePhysicalDnsDomain = 6
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace ComputerSystem {
  public class Identification {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    static extern bool SetComputerNameEx(int NameType, string lpBuffer);
    public static bool SetPrimaryDnsSuffix(string suffix) {
      try {
        return SetComputerNameEx($ComputerNamePhysicalDnsDomain, suffix);
      }
      catch (Exception) {
        return false;
      }
    }
  }
}
"@
  [ComputerSystem.Identification]::SetPrimaryDnsSuffix($Suffix)
}
write-host "watch and learn ..."
if( Set-PrimaryDnsSuffix "#{suffix}") {
  exit 0
} else {
  exit 1
}
EOH
          machine.communicate.execute(
            script,
            error_class: Errors::RenameComputerFailed,
            error_key: :rename_computer_failed)
          return true
        end

        def self.really_change_host_name(machine, name)
          # If the configured name matches the current name, then bail
          # We cannot use %ComputerName% because it truncates at 15 chars
          return false if machine.communicate.test("if ([System.Net.Dns]::GetHostName() -eq '#{name}') { exit 0 } exit 1")

          # Rename and reboot host if rename succeeded
          script = <<-EOH
            $computer = Get-WmiObject -Class Win32_ComputerSystem
            $retval = $computer.rename("#{name}").returnvalue
            write-host "watch and learn ..."
            if ($retval -eq 0) {
              exit 0
            } else {
              exit 1
            }
          EOH

          machine.communicate.execute(
            script,
            error_class: Errors::RenameComputerFailed,
            error_key: :rename_computer_failed)
          return true
        end

      end
    end
    module Errors
      # A convenient superclass for all our errors.
      class WindowsError < Vagrant::Errors::VagrantError
        error_namespace("vagrant_windows.errors")
      end

      class NetworkWinRMRequired < WindowsError
        error_key(:network_winrm_required)
      end

      class RenameComputerFailed < WindowsError
        error_key(:rename_computer_failed)
      end
    end
  end
end
