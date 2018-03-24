# frozen_string_literal: true

require_relative '../lib/asana_api_client.rb'

WORKSPACE_AND_PROJECT_DIC = YAML.load_file(File.expand_path('../resources/workspace_and_project_dic.yml', __dir__))

WORKSPACE_AND_PROJECT_DIC.each do |workspace_and_project_pair_one, workspace_and_project_pair_two|
  AsanaApiClient.new(workspace_and_project_pair_one, workspace_and_project_pair_two).sync_tasks
  AsanaApiClient.new(workspace_and_project_pair_two, workspace_and_project_pair_one).sync_tasks
end
