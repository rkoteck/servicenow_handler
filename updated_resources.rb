#
# Copyright:: 2018, Company Name <company@email.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'chef/handler'
require 'json'
require 'socket'

module ServiceNowReport
  class UpdatedResources < Chef::Handler
    def savetime
      Time.now.strftime('%Y%m%d%H%M%S')
    end

    def report
      # Set up some variables used in report
      updated_resource_count = run_status.updated_resources.length
      chef_status = if run_status.success?
                      'SUCCESS'
                    else
                      'FAILURE'
                    end

      if run_status.updated_resources.length.to_i > 0
        build_report_dir
        File.open(File.join('/var/chef/reports', "chef-update-report-#{savetime}.txt"), 'w') do |file|
          file.puts("\nChef client run status: #{chef_status}\n")
          file.puts("Chef updated #{updated_resource_count} resources:\n\n")
          run_status.updated_resources.each do |resource|
            u = "recipe[#{resource.cookbook_name}::#{resource.recipe_name}] ran '#{resource.action}' on #{resource.resource_name} '#{resource.name}'"
            file.puts(u.to_s)
          end
        end

        if run_status.success?
          build_json
          snow_api
          clean_up
        end
      else
        Chef::Log.info 'No Resources updated this run!'
      end
    end

    def build_report_dir
      unless File.exist?('/var/chef/reports')
        FileUtils.mkdir_p('/var/chef/reports')
        File.chmod(00744, '/var/chef/reports')
      end
    end

    def build_json
      # Gather some variables
      hostname = Socket.gethostname[/^[^.]+/]
      file = File.open("/var/chef/reports/chef-update-report-#{savetime}.txt")
      data = ''
      file.each { |line| data << line }
      t = Time.now
      st = t + (60 * 60 * 2)
      et = t + (60 * 60 * 3)

      json_hash = {
        'category' => 'server',
        'type' => 'standard',
        'u_standard_change' => 'standard change name',
        'assignment_group' => 'dcloud',
        'cmdb_ci' => hostname.to_s,
        'short_description' => 'short description',
        'description' => data.to_s,
        'impact' => '4',
        'priority' => '4',
        'opened_by' => 'SERVICENOW_ID',
        'assigned_to' => 'SERVICENOW_ID',
        'u_ihs_flag' => 'false',
        'u_psi_flag' => 'false',
        'state' => '3',
        'u_stage' => 'completed',
        'u_completion_code' => 'successful',
        'start_date' => st.to_s,
        'end_date' => et.to_s,
        'approval' => 'requested',
      }
      File.open('/var/chef/reports/updated_resources.json', 'w') do |f|
        f.write(json_hash.to_json)
      end
    end

    def snow_api
      uname = 'SERVICENOW_ID'
      pwd = 'INSERT_PASSWORD'
      proxy = 'proxy.somecompany.com:1234'
      url = 'https://companyname.service-now.com/api/now/v2/table/change_request'
      request = 'POST'
      header1 = 'Accept:application/json'
      header2 = 'Content-Type:application/json'
      data = '@/var/chef/reports/updated_resources.json'
      puts `curl -x #{proxy} #{url} --request #{request} --header #{header1} --header #{header2} --data #{data} --user #{uname}:#{pwd}`
    end

    def clean_up
      FileUtils.rm('/var/chef/reports/updated_resources.json')
    end
  end
end
