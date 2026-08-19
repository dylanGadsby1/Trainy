require 'xcodeproj'
project_path = 'Trainy.xcodeproj'
project = Xcodeproj::Project.open(project_path)
widget_target = project.targets.find { |t| t.name == 'Trainy RTT API Live ActivitiesExtension' }
group = project.main_group
file_reference = group.files.find { |f| f.path == 'TrainyActivityAttributes.swift' }

if widget_target && file_reference
  unless widget_target.source_build_phase.files.any? { |bf| bf.file_ref == file_reference }
    widget_target.source_build_phase.add_file_reference(file_reference)
    puts "Added to widget target"
  else
    puts "Already in widget target"
  end
else
  puts "Target or file not found"
end
project.save
