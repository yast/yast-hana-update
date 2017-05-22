require 'socket'
require 'hana_update/shell_commands'

class ClusterCallError < RuntimeError
end

module HANAUpdater
    class ClusterResource
    end

    class ClusterNode
        include ShellCommands

        def initialize
            @name = 'hana01'
        end

        def localhost?
            @name == Socket.gethostname
        end

        def maintenance_mode(on: true)
            value = on ? 'on' : 'off'
            set_attribute(@name, 'maintenance', value)
            true
        end

        def maintenance_mode?
            get_attribute(@name, 'maintenance') == 'on'
        end

        private

        def get_attribute(node_name, attribute_name)
            out, status = exec_outerr_status('crm_attribute', '--node', node_name, '--name', attribute_name, '--query', '--quiet')
            raise ClusterCallError(out) unless status.exitstatus == 0
            out.strip
        end

        def set_attribute(node_name, attribute_name, value)
            out, status = exec_outerr_status('crm_attribute', '--type', 'nodes', '--node', @name, '--name', attribute_name, '--update', value)
            raise ClusterCallError(out) unless status.exitstatus == 0
        end
    end

    class ClusterState
        # uses both cibadmin -Ql and crm_mon -r --as-xml output
    end
end
