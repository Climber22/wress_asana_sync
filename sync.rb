# frozen_string_literal: true

require 'asana'

class InvalidSectionNameError < StandardError; end
class InvalidWorkspaceNameError < StandardError; end

class AsanaApiClient
  TASK_FIELDS = %i[
    completed
    custom_fields
    due_on
    due_at
    external
    hearted
    name
    notes
    start_on
  ].freeze

  def initialize(old_workspace_and_project, new_workspace_and_project)
    @client = Asana::Client.new do |c|
      c.authentication :access_token, ENV['ASANA_ACCESS_TOKEN']
    end
    @src_workspace = find_workspace_by_name(old_workspace_and_project[:workspace])
    @src_project = find_project_by_name(@src_workspace.id, old_workspace_and_project[:project])
    @dest_workspace = find_workspace_by_name(new_workspace_and_project[:workspace])
    @dest_project = find_project_by_name(@dest_workspace.id, new_workspace_and_project[:project])
  end

  def sync_tasks
    src_tasks = tasks_in_project(@src_project.id)
    src_tasks.each do |src_task|
      cp_task(src_task, @dest_workspace.id) unless task_exists?(src_task, @dest_project.id)
    end
  end

  def task_exists?(searched_task, target_project_id)
    tasks_in_project(target_project_id).each do |target_task|
      return true if searched_task.name == target_task.name
    end
    false
  end

  def format_for_request(src_task)
    formatted_task = { memberships: cp_memberships(src_task) }
    TASK_FIELDS.each do |task_filed|
      formatted_task[task_filed] = src_task.to_h[task_filed.to_s]
    end
    formatted_task.reject { |_key, value| value.nil? }
  end

  def cp_task(src_task, dest_workspace_id)
    Asana::Resources::Task.create_in_workspace(@client, workspace: dest_workspace_id, options: {}, **format_for_request(src_task))
  end

  def cp_memberships(src_task)
    src_task.memberships.map do |src_membership|
      section = find_section_by_name(@dest_project, src_membership['section']['name'])
      {
        project: @dest_project.id,
        section: section.id
      }
    end
  end

  def tasks_in_project(project_id)
    Asana::Resources::Task.find_all(@client, project: project_id).map do |task|
      Asana::Resources::Task.find_by_id(@client, task.id)
    end
  end

  def projects_in_workspace(workspace_id)
    Asana::Resources::Project.find_all(@client, workspace: workspace_id).elements
  end

  def find_section_by_name(project, section_name)
    project.sections.elements.find { |section| section.name == section_name } || (raise InvalidSectionNameError, "#{section_name} is invalid")
  end

  def find_project_by_name(workspace_id, project_name)
    projects_in_workspace(workspace_id).find { |project| project.name == project_name } || (raise InvalidWorkspaceNameError, "#{workspace_name} is invalid")
  end

  def find_workspace_by_name(workspace_name)
    workspaces.find { |workspace| workspace.name == workspace_name } || (raise InvalidWorkspaceNmaeError, "#{workspace_name} is invalid")
  end

  def workspaces
    @workspaces ||= Asana::Resources::Workspace.find_all(@client).elements
  end
end
