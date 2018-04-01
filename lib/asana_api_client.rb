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

  def initialize(src_workspace_and_project, dest_workspace_and_project)
    @client = Asana::Client.new do |c|
      c.authentication :access_token, ENV['ASANA_ACCESS_TOKEN']
    end
    @src_project = find_project_by_name(src_workspace_and_project)
    @dest_project = find_project_by_name(dest_workspace_and_project)
  end

  def src_tasks
    @src_tasks ||= tasks_in_project(@src_project.id)
  end

  def dest_tasks
    @dest_tasks ||= tasks_in_project(@dest_project.id)
  end

  def sync_tasks
    src_tasks.each do |src_task|
      same_name_dest_task = find_same_name_dest_task(src_task, dest_tasks)
      same_name_dest_task ? update_task_and_stories(src_task, same_name_dest_task) : cp_task_and_stories(src_task)
    end
  end

  def find_same_name_dest_task(src_task, dest_tasks)
    dest_tasks.find { |dest_task| dest_task.name == src_task.name }
  end

  def comments(task)
    task.stories.elements.reject { |story| story.type == 'system' }.map(&:text)
  end

  def same_memberships_at_dest_project(task)
    task.memberships.map do |membership|
      section = find_section_by_name(@dest_project, membership['section']['name'])
      {
        project: @dest_project.id,
        section: section.id
      }
    end
  end

  def task_info_lists(task)
    info_lists = {}
    TASK_FIELDS.each do |task_filed|
      info_lists[task_filed] = task.to_h[task_filed.to_s]
    end
    info_lists.reject { |_key, value| value.nil? }
  end

  def task_params_for_create(task)
    task_info_lists(task).merge(memberships: same_memberships_at_dest_project(task))
  end

  def update_task_and_stories(src_task, dest_task)
    update_task(src_task, dest_task)
    update_memberships(src_task, dest_task)
    update_stories(src_task, dest_task)
  end

  def update_task(src_task, dest_task)
    dest_task_info_lists_memo = task_info_lists(dest_task)
    diff_task_info_lists = task_info_lists(src_task).reject { |key, val| val == dest_task_info_lists_memo[key] }
    dest_task.update(**diff_task_info_lists) if diff_task_info_lists
  end

  def update_memberships(src_task, dest_task)
    diff_memberships = same_memberships_at_dest_project(src_task) - same_memberships_at_dest_project(dest_task)
    dest_task.add_project(project: @dest_project.id, section: diff_memberships.first[:section]) if diff_memberships.any?
  end

  def update_stories(src_task, dest_task)
    diff_comments = comments(src_task) - comments(dest_task)
    diff_comments&.each { |comment| Asana::Resources::Story.create_on_task(@client, task: dest_task.id, text: comment) }
  end

  def cp_task_and_stories(src_task)
    dest_task = cp_task(src_task)
    cp_stories(src_task, dest_task)
  end

  def cp_task(src_task)
    Asana::Resources::Task.create(@client, projects: [@dest_project.id], options: {}, **task_params_for_create(src_task))
  end

  def cp_stories(src_task, dest_task)
    src_task.stories.elements.reject { |story| story.type == 'system' }.each do |story|
      Asana::Resources::Story.create_on_task(@client, task: dest_task.id, text: story.text)
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

  def find_project_by_name(workspace_and_project)
    workspace = find_workspace_by_name(workspace_and_project[:workspace])
    projects_in_workspace(workspace.id).find { |project| project.name == workspace_and_project[:project] } || (raise InvalidWorkspaceNameError, "#{workspace_name} is invalid")
  end

  def find_workspace_by_name(workspace_name)
    workspaces.find { |workspace| workspace.name == workspace_name } || (raise InvalidWorkspaceNmaeError, "#{workspace_name} is invalid")
  end

  def workspaces
    @workspaces ||= Asana::Resources::Workspace.find_all(@client).elements
  end
end
