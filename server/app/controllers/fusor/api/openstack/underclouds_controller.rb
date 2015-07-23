#
# Copyright 2015 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

require 'egon/undercloud/commands'
require 'egon/undercloud/ssh-connection'
require 'egon/undercloud/installer'

module Fusor
  module Api
    module Openstack
      class UndercloudsController < Api::Openstack::BaseController

        def wait_and_log(installer, stringio)
          lastpos = 0
          while !installer.completed?
            sleep 1
            current = stringio.size
            if (lastpos != current)
              stringio.seek(lastpos)
              Rails.logger.info stringio.read(current - lastpos)
              lastpos = current
            end
          end
        end

        def create
          underhost = params[:underhost]
          underuser = params[:underuser]
          underpass = params[:underpass]
          # TODO: switch to satellite
          portal_user = params[:portal_user]
          portal_pass = params[:portal_pass]
          portal_pool = params[:portal_pool]

          ssh = Egon::Undercloud::SSHConnection.new(underhost, underuser, underpass)
          io = StringIO.new
          installer = Egon::Undercloud::Installer.new(ssh)
          # TODO: switch to satellite
          installer.install(Egon::Undercloud::Commands.OSP7_vanilla_rhel(portal_user, portal_pass, portal_pool), io)
          wait_and_log(installer, io)
          Rails.logger.info "undercloud install complete"
          Rails.logger.info "installer.started? #{installer.started?}"
          Rails.logger.info "installer.completed? #{installer.completed?}"
          Rails.logger.info "installer.error? #{installer.failure?}"
          install_failure = installer.failure?
          installer.check_ports
          port_failure = installer.failure?

          io = StringIO.new
          ssh.execute("hiera admin_password", io)
          admin = io.string
          # TODO: save admin credentials, remove logging
          Rails.logger.info "TODO: admin password #{admin}"

          io = StringIO.new
          installer.set_completed(false)
          installer.install(POST_INSTALL, io)
          wait_and_log(installer, io)

          render :json => [admin, installer, install_failure, port_failure]
        end

        # TODO: remove when fusor/egon pull request is merged
        POST_INSTALL = "
        source stackrc
        source tripleo-undercloud-passwords

        tripleo setup-overcloud-passwords -o tripleo-overcloud-passwords
        source tripleo-overcloud-passwords
        NeutronFlatNetworks=${NeutronFlatNetworks:-'datacentre'}
        NeutronPhysicalBridge=${NeutronPhysicalBridge:-'br-ex'}
        NeutronBridgeMappings=${NeutronBridgeMappings:-'datacentre:br-ex'}
        # Define the interface that will be bridged onto the Neutron defined
        # network.
        NeutronPublicInterface=${NeutronPublicInterface:-nic1}
        HypervisorNeutronPublicInterface=${HypervisorNeutronPublicInterface:-$NeutronPublicInterface}
        NEUTRON_NETWORK_TYPE=${NEUTRON_NETWORK_TYPE:-gre}
        NEUTRON_TUNNEL_TYPES=${NEUTRON_TUNNEL_TYPES:-gre}
        # Define the overcloud libvirt type for virtualization. kvm for
        # baremetal, qemu for an overcloud running in vm's.
        OVERCLOUD_LIBVIRT_TYPE=${OVERCLOUD_LIBVIRT_TYPE:-qemu}
        NtpServer=${NtpServer:-""}
        CONTROLSCALE=${CONTROLSCALE:-1}
        COMPUTESCALE=${COMPUTESCALE:-1}
        CEPHSTORAGESCALE=${CEPHSTORAGESCALE:-0}
        BLOCKSTORAGESCALE=${BLOCKSTORAGESCALE:-0}
        SWIFTSTORAGESCALE=${SWIFTSTORAGESCALE:-0}

        # Default all image parameters to use overcloud-full
        OVERCLOUD_CONTROLLER_IMAGE=${OVERCLOUD_CONTROLLER_IMAGE:-overcloud-full}
        OVERCLOUD_COMPUTE_IMAGE=${OVERCLOUD_COMPUTE_IMAGE:-overcloud-full}
        OVERCLOUD_BLOCKSTORAGE_IMAGE=${OVERCLOUD_BLOCKSTORAGE_IMAGE:-overcloud-full}
        OVERCLOUD_SWIFTSTORAGE_IMAGE=${OVERCLOUD_SWIFTSTORAGE_IMAGE:-overcloud-full}
        OVERCLOUD_CEPHSTORAGE_IMAGE=${OVERCLOUD_CEPHSTORAGE_IMAGE:-overcloud-full}

        # Default flavor parameters
        export OVERCLOUD_CONTROL_FLAVOR=${OVERCLOUD_CONTROL_FLAVOR:-\"baremetal\"}
        export OVERCLOUD_COMPUTE_FLAVOR=${OVERCLOUD_COMPUTE_FLAVOR:-\"baremetal\"}
        export OVERCLOUD_CEPHSTORAGE_FLAVOR=${OVERCLOUD_CEPHSTORAGE_FLAVOR:-\"baremetal\"}
        # Even though we are not deploying nodes with these roles, the templates will
        # still validate that a flavor exists, so just use the baremetal_compute flavor
        # for now.
        export OVERCLOUD_BLOCKSTORAGE_FLAVOR=${OVERCLOUD_BLOCKSTORAGE_FLAVOR:-\"baremetal\"}
        export OVERCLOUD_SWIFTSTORAGE_FLAVOR=${OVERCLOUD_SWIFTSTORAGE_FLAVOR:-\"baremetal\"}

        export OVERCLOUD_RESOURCE_REGISTRY=${OVERCLOUD_RESOURCE_REGISTRY:-\"/usr/share/openstack-tripleo-heat-templates/overcloud-resource-registry-puppet.yaml\"}
        NeutronControlPlaneID=$(neutron net-show ctlplane | grep ' id ' | awk '{print $4}')

        export OVERCLOUD_EXTRA=${OVERCLOUD_EXTRA:-""}

        PLAN_ID=$(tuskar plan-show overcloud | awk '$2==\"uuid\" {print $4}')
        if [ -n \"$PLAN_ID\" ]; then
            tuskar plan-delete $PLAN_ID
        fi

        tuskar plan-create overcloud
        PLAN_ID=$(tuskar plan-show overcloud | awk '$2==\"uuid\" {print $4}')

        CONTROLLER_ID=$(tuskar role-list | awk '$4==\"Controller\" {print $2}')
        COMPUTE_ID=$(tuskar role-list | awk '$4==\"Compute\" {print $2}')
        SWIFT_ID=$(tuskar role-list | awk '$4==\"Swift-Storage\" {print $2}')
        CINDER_ID=$(tuskar role-list | awk '$4==\"Cinder-Storage\" {print $2}')
        CEPH_ID=$(tuskar role-list | awk '$4==\"Ceph-Storage\" {print $2}')

        tuskar plan-add-role $PLAN_ID -r $CONTROLLER_ID
        tuskar plan-add-role $PLAN_ID -r $COMPUTE_ID
        tuskar plan-add-role $PLAN_ID -r $SWIFT_ID
        tuskar plan-add-role $PLAN_ID -r $CINDER_ID
        tuskar plan-add-role $PLAN_ID -r $CEPH_ID

        export TUSKAR_PARAMETERS=${TUSKAR_PARAMETERS:-\"
        -A NeutronControlPlaneID=${NeutronControlPlaneID}
        -A Controller-1::AdminPassword=${OVERCLOUD_ADMIN_PASSWORD}
        -A Controller-1::AdminToken=${OVERCLOUD_ADMIN_TOKEN}
        -A Compute-1::AdminPassword=${OVERCLOUD_ADMIN_PASSWORD}
        -A Controller-1::SnmpdReadonlyUserPassword=${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}
        -A Cinder-Storage-1::SnmpdReadonlyUserPassword=${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}
        -A Swift-Storage-1::SnmpdReadonlyUserPassword=${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}
        -A Compute-1::SnmpdReadonlyUserPassword=${UNDERCLOUD_CEILOMETER_SNMPD_PASSWORD}
        -A Controller-1::CeilometerPassword=${OVERCLOUD_CEILOMETER_PASSWORD}
        -A Controller-1::CeilometerMeteringSecret=${OVERCLOUD_CEILOMETER_SECRET}
        -A Compute-1::CeilometerPassword=${OVERCLOUD_CEILOMETER_PASSWORD}
        -A Compute-1::CeilometerMeteringSecret=${OVERCLOUD_CEILOMETER_SECRET}
        -A Controller-1::CinderPassword=${OVERCLOUD_CINDER_PASSWORD}
        -A Controller-1::GlancePassword=${OVERCLOUD_GLANCE_PASSWORD}
        -A Controller-1::HeatPassword=${OVERCLOUD_HEAT_PASSWORD}
        -A Controller-1::NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD}
        -A Compute-1::NeutronPassword=${OVERCLOUD_NEUTRON_PASSWORD}
        -A Controller-1::NovaPassword=${OVERCLOUD_NOVA_PASSWORD}
        -A Compute-1::NovaPassword=${OVERCLOUD_NOVA_PASSWORD}
        -A Controller-1::SwiftHashSuffix=${OVERCLOUD_SWIFT_HASH}
        -A Controller-1::SwiftPassword=${OVERCLOUD_SWIFT_PASSWORD}
        -A Controller-1::CinderISCSIHelper=lioadm
        -A Cinder-Storage-1::CinderISCSIHelper=lioadm
        -A Controller-1::CloudName=overcloud
        -A Controller-1::NeutronPublicInterface=$NeutronPublicInterface
        -A Controller-1::NeutronBridgeMappings=$NeutronBridgeMappings
        -A Compute-1::NeutronBridgeMappings=$NeutronBridgeMappings
        -A Controller-1::NeutronFlatNetworks=$NeutronFlatNetworks
        -A Compute-1::NeutronFlatNetworks=$NeutronFlatNetworks
        -A Compute-1::NeutronPhysicalBridge=$NeutronPhysicalBridge
        -A Compute-1::NeutronPublicInterface=$NeutronPublicInterface
        -A Compute-1::NovaComputeLibvirtType=$OVERCLOUD_LIBVIRT_TYPE
        -A Controller-1::NtpServer=${NtpServer}
        -A Compute-1::NtpServer=${NtpServer}
        -A Controller-1::NeutronNetworkType=${NEUTRON_NETWORK_TYPE}
        -A Compute-1::NeutronNetworkType=${NEUTRON_NETWORK_TYPE}
        -A Controller-1::NeutronTunnelTypes=${NEUTRON_TUNNEL_TYPES}
        -A Compute-1::NeutronTunnelTypes=${NEUTRON_TUNNEL_TYPES}
        -A Controller-1::count=${CONTROLSCALE}
        -A Compute-1::count=${COMPUTESCALE}
        -A Swift-Storage-1::count=${SWIFTSTORAGESCALE}
        -A Cinder-Storage-1::count=${BLOCKSTORAGESCALE}
        -A Ceph-Storage-1::count=${CEPHSTORAGESCALE}
        -A Cinder-Storage-1::Flavor=${OVERCLOUD_BLOCKSTORAGE_FLAVOR}
        -A Compute-1::Flavor=${OVERCLOUD_COMPUTE_FLAVOR}
        -A Controller-1::Flavor=${OVERCLOUD_CONTROL_FLAVOR}
        -A Swift-Storage-1::Flavor=${OVERCLOUD_SWIFTSTORAGE_FLAVOR}
        -A Ceph-Storage-1::Flavor=${OVERCLOUD_CEPHSTORAGE_FLAVOR}
        -A Swift-Storage-1::Image=${OVERCLOUD_SWIFTSTORAGE_IMAGE}
        -A Cinder-Storage-1::Image=${OVERCLOUD_BLOCKSTORAGE_IMAGE}
        -A Ceph-Storage-1::Image=${OVERCLOUD_BLOCKSTORAGE_IMAGE}
        -A Controller-1::Image=${OVERCLOUD_CONTROLLER_IMAGE}
        -A Compute-1::Image=${OVERCLOUD_COMPUTE_IMAGE}
        \"}

        if [ $CONTROLSCALE -gt 1 ]; then
            export TUSKAR_PARAMETERS=\"$TUSKAR_PARAMETERS
            -A Controller-1::NeutronL3HA=True
            -A Controller-1::NeutronAllowL3AgentFailover=False
            -A Compute-1::NeutronL3HA=True
            -A Compute-1::NeutronAllowL3AgentFailover=False
            \"
        fi

        if [ $CEPHSTORAGESCALE -gt 0 ]; then
            FSID=$(uuidgen)
            MON_KEY=$(create_cephx_key)
            ADMIN_KEY=$(create_cephx_key)
            CINDER_ISCSI=${CINDER_ISCSI:-0}
            export TUSKAR_PARAMETERS=\"$TUSKAR_PARAMETERS
            -A Controller-1::CinderEnableRbdBackend=True
            -A Controller-1::GlanceBackend=rbd
            -A CephClusterFSID=$FSID
            -A CephMonKey=$MON_KEY
            -A CephAdminKey=$ADMIN_KEY
            -A Compute-1::NovaEnableRbdBackend=True
            \"

            if [ $CINDER_ISCSI -eq 0 ]; then
                export TUSKAR_PARAMETERS=\"$TUSKAR_PARAMETERS
                -A Controller-1::CinderEnableIscsiBackend=false
                \"
            else
                # (this is the default parameter value)
                export TUSKAR_PARAMETERS=\"$TUSKAR_PARAMETERS
                       -A Controller-1::CinderEnableIscsiBackend=true
                       \"
            fi
        fi

        tuskar plan-update $TUSKAR_PARAMETERS $PLAN_ID

        # Added next to parameters as they are required
        TIMEOUT=5
        HEAT_OP=\"stack-create\"

        HEAT_ENV=${HEAT_ENV:-\"overcloud-env.json\"}

        if [ -f $HEAT_ENV -a \"$HEAT_OP\" = \"stack-update\" ]; then
            ENV_JSON=$(cat $HEAT_ENV)
        else
            ENV_JSON='{\"parameters\":{}}'
        fi

        jq . > \"${HEAT_ENV}\" <<< $ENV_JSON
        chmod 0600 \"${HEAT_ENV}\"

        if [ \"$HEAT_OP\" = \"stack-create\" ]; then
          generate-keystone-pki --heatenv $HEAT_ENV
        fi

        KeystoneCACertificate=$(os-apply-config -m $HEAT_ENV --key parameters.KeystoneCACertificate --type raw)
        KeystoneSigningCertificate=$(os-apply-config -m $HEAT_ENV --key parameters.KeystoneSigningCertificate --type raw)
        KeystoneSigningKey=$(os-apply-config -m $HEAT_ENV --key parameters.KeystoneSigningKey --type raw)

        # Sending the Certificates one by one, otherwise there are problems with escaping
        tuskar plan-update -A Controller-1::KeystoneCACertificate=\"${KeystoneCACertificate}\" $PLAN_ID
        tuskar plan-update -A Controller-1::KeystoneSigningCertificate=\"${KeystoneSigningCertificate}\" $PLAN_ID
        tuskar plan-update -A Controller-1::KeystoneSigningKey=\"${KeystoneSigningKey}\" $PLAN_ID

        # Get templates from tuskar
        tuskar plan-templates -O tuskar_templates $PLAN_ID

        OVERCLOUD_YAML_PATH=\"tuskar_templates/plan.yaml\"
        ENVIRONMENT_YAML_PATH=\"tuskar_templates/environment.yaml\"
        "

      end
    end
  end
end
