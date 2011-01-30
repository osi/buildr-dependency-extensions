require 'buildr/core/project'
require 'yaml'

module BuildrDependencyExtensions
  module TransitiveDependencies

    include Extension

    def self.extended(base)
      class << base

        attr_accessor :transitive_scopes

        def conflict_resolver
          # @conflict_resolver ||= HighestVersionConflictResolver.new
          @conflict_resolver ||= MavenVersionConflictResolver.new
        end
      end
      super
    end

    after_define(:'transitive-dependencies' => :run) do |project|
      if project.transitive_scopes
        resolve_compile_dependencies project if project.transitive_scopes.include? :compile
        resolve_runtime_dependencies project if project.transitive_scopes.include? :run
        resolve_test_dependencies    project if project.transitive_scopes.include? :test
      end
    end

    module_function

    def resolve_compile_dependencies project
      original_file_tasks   = project.compile.dependencies.reject {|dep| HelperFunctions.is_artifact? dep }
      original_dependencies = project.compile.dependencies.select {|dep| HelperFunctions.is_artifact? dep }
      new_dependencies = []
      original_dependencies.each do |dependency|
        add_dependency project, new_dependencies, dependency, ["compile"]
      end
      new_dependencies = resolve_conflicts(project, new_dependencies.uniq)
      project.compile.dependencies = new_dependencies + original_file_tasks
    end

    def resolve_runtime_dependencies project
      original_file_tasks   = project.run.classpath.reject {|dep| HelperFunctions.is_artifact? dep }
      original_dependencies = project.run.classpath.select {|dep| HelperFunctions.is_artifact? dep }
      new_dependencies = []
      original_dependencies.each do |dependency|
        add_dependency project, new_dependencies, dependency, ["compile", "runtime"]
      end
      new_dependencies = resolve_conflicts(project, new_dependencies.uniq)
      project.run.classpath = new_dependencies + original_file_tasks
    end

    def resolve_test_dependencies project
      original_file_tasks   = project.test.classpath.reject {|dep| HelperFunctions.is_artifact? dep }
      original_dependencies = project.test.classpath.select {|dep| HelperFunctions.is_artifact? dep }
      new_dependencies = []
      original_dependencies.each do |dependency|
        add_dependency project, new_dependencies, dependency, ["compile", "runtime"]
      end
      new_dependencies = resolve_conflicts(project, new_dependencies.uniq)
      project.test.classpath = new_dependencies + original_file_tasks
    end

    def add_dependency project, new_dependencies, dependency, scopes, depth = 0
      scopes.each do |scope|
        POM.load(dependency.pom).dependencies(scope).each do |dep|
          artifact = project.artifact(dep)
          add_dependency project, new_dependencies, artifact, scopes, (depth + 1)
        end
      end
      dependency.depth = depth
      new_dependencies << dependency
    end

    def resolve_conflicts project, dependencies
      unique_transitive_artifacts = HelperFunctions.get_unique_group_artifact(dependencies)
      new_scope_artifacts = unique_transitive_artifacts.map do |artifact|
        artifact_hash = Artifact.to_hash(artifact)
        artifact_hash[:version] = project.conflict_resolver.resolve(artifact, dependencies)
        project.artifact(Artifact.to_spec(artifact_hash))
      end
      new_scope_artifacts
    end
  end
end
