# This file is part of the openvpn_management library for Ruby.
# Copyright (C) 2012 Davide Guerri
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require "rubygems"
require 'net/telnet'

cwd = File.expand_path(File.dirname(__FILE__))
$: << cwd
#noinspection RubyResolve
require File.join(cwd, "openvpn_management", "version")


class OpenvpnManagement

  # Create a new openvpn telnet session. Need host and port of server and optionally password for login.
  def initialize(options)
    telnet_options = {}

    telnet_options["Host"]     = options[:host] || "localhost"
    telnet_options["Port"]     = options[:port] || 1194
    telnet_options["Timeout"]  = options[:timeout] || 10
    password = options[:password]

    telnet_options["Prompt"] = />INFO:OpenVPN.*\n/

    @sock = Net::Telnet::new(telnet_options)

    unless password.nil?
      @sock.login("LoginPrompt" => /ENTER PASSWORD:/, "Name" => password)
    end
  end

  # Destroy an openvpn_management telnet session.
  def destroy
    @sock.close
  end

  # Get information about clients connected list and routing table. Return two arrays of arrays with lists inside.
  # For each client in client_list array there is: Common Name, Addressing Infos, Bytes in/out, Uptime.
  # Instead for each route entry there is: IP/Eth Address (depend on tun/tap mode), Addressing, Uptime.
  def status
    client_list_flag = 0, routing_list_flag = 0
    clients = {}
    routes = {}

    c = issue_command "status"
    c.each do |l|

      # End Information Markers
      if l == "ROUTING TABLE\n"
        client_list_flag = 0
      end

      if l == "GLOBAL STATS\n"
        routing_list_flag = 0
      end

      # Update Clients Connected List
      # Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since
      if client_list_flag == 1
        client = l.split(',')
        clients[client[0]] ||= []
        clients[client[0]] << {
            :real_address => client[1],
            :bytes_received => client[2],
            :bytes_sent => client[3],
            :connected_since => client[4].chop
        }
      end

      # Update Routing Info List
      # Virtual Address,Common Name,Real Address,Last Ref
      if routing_list_flag == 1
        route = l.split(',')
        routes[route[0]] = { :common_name => route[1], :real_address=> route[2], :last_ref => route[3].chop }
      end

      # Start Information Markers
      if l == "Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since\n"
        client_list_flag = 1
      end

      if l == "Virtual Address,Common Name,Real Address,Last Ref\n"
        routing_list_flag = 1
      end
    end

    { :clients => clients, :routes => routes }
  end

  # Get information about number of clients connected and traffic statistic (byte in & byte out).
  def stats
    stats_info = issue_command("load-stats").split(',')
    {
        :clients => stats_info[0].gsub("nclients=", "").to_i,
        :bytes_download => stats_info[1].gsub("bytesin=", "").to_i,
        :bytes_upload => stats_info[2].chop!.gsub("bytesout=", "").to_i
    }
  end

  # Returns a string showing the processes and management interface's version.
  def version
    issue_command "version"
  end

  # Show process ID of the current OpenVPN process.
  def pid
    issue_command "pid"
  end

  # Send signal s to daemon, where s can be SIGHUP, SIGTERM, SIGUSR1, SIGUSR2.
  def signal(s)
    if %w(SIGHUP SIGTERM SIGUSR1 SIGUSR2).include? s
      issue_command "signal #{s}"
    else
      raise ArgumentError "Unsupported signal '#{s}' (Supported signals: SIGHUP, SIGTERM, SIGUSR1, SIGUSR2)"
    end
  end

  # Set log verbosity level to n, or show if n is absent.
  def verb(n=-1)
    issue_command(n >= 0 ? "verb #{n}" : "verb")
  end

  # Set log mute level to n, or show level if n is absent.
  def mute(n=-1)
    issue_command(n >= 0 ? "mute #{n}" : "mute")
  end

  # Kill the client instance(s) by common name of host:port combination.
  def kill(options)
    cn = options[:common_name]
    host = options[:host]
    port = options[:port]

    if cn.nil?
      if !host.nil? && !port.nil?
        issue_command "kill #{host}:#{port}"
      else
        raise RuntimeError.new ":common_name or :host + :port combination needed"
      end
    else
      issue_command "kill #{cn}"
    end
  end

  private

  def issue_command(cmd)
    c = @sock.cmd("String" => cmd, "Match" => /(SUCCESS:.*\n|ERROR:.*\n|END.*\n)/)
    if c =~ /\AERROR\: (.+)\n\Z/
      raise RuntimeError.new Regexp.last_match 1
    elsif c =~ /\ASUCCESS\: (.+)\n\Z/
      Regexp.last_match 1
    else
      c
    end
  end

end
