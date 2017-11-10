# module Rebi
#   class IAM
#
#     attr_reader :client
#
#     def initialize client=Aws::IAM::Client.new
#       @client = client
#     end
#
#     def check_or_create_eb_profile profile
#
#     end
#
#     def create_instance_profile profile
#       clieng.create_instance_profile({
#         instance_profile_name: profile
#         })
#     end
#
#     def get_default_role
#       role = Rebi::ConfigEnvironment::DEFAULT_IAM_INSTANCE_PROFILE
#       document = '{"Version": "2008-10-17","Statement": [{"Action":' \
#                  ' "sts:AssumeRole","Principal": {"Service": ' \
#                  '"ec2.amazonaws.com"},"Effect": "Allow","Sid": ""}]}'
#       client.create_role({
#           role_name: role,
#           assume_role_policy_document: document
#         })
#       return role
#     end
#
#     def add_role_to_profile profile, role
#       client.add_role_to_instance_profile({
#         instance_profile_name: profile,
#         role_name: role
#         })
#     end
#
#     def log mes
#       Rebi.log(mes, "IAM")
#     end
#   end
# end
