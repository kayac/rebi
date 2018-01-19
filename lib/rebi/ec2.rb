module Rebi
  class EC2

    include Rebi::Log

    attr_reader :client

    def initialize client
      @client = client
    end

    def log_label
      "EC2"
    end

    def describe_instance instance_id
      res = client.describe_instances instance_ids: [instance_id]
      return res.reservations.first.instances.first
    end

    def authorize_ssh instance_id, &blk
      group_id = describe_instance(instance_id).security_groups.map(&:group_id).sort.first

      my_ip = `dig +short myip.opendns.com @resolver1.opendns.com`.chomp
      cidr_ip = my_ip.present? ? "#{my_ip}/32" : "0.0.0.0/0"

      begin
        log "Attempting to open port 22."
        client.authorize_security_group_ingress({
          group_id: group_id,
          ip_protocol: "tcp",
          to_port: 22,
          from_port: 22,
          cidr_ip: cidr_ip
          })
        log "SSH port 22 open."

      rescue Aws::EC2::Errors::InvalidPermissionDuplicate
        log "Opened already"
      rescue Exception => e
        raise e
      end

      yield if block_given?

      ensure
        begin
          log "Attempting to close port 22."
          client.revoke_security_group_ingress({
            group_id: group_id,
            ip_protocol: "tcp",
            to_port: 22,
            from_port: 22,
            cidr_ip: cidr_ip
            })
        rescue Exception => e
          raise e
        end
    end

  end
end
