require 'rubygems'

require 'rest-client'
require 'json'
require 'openstudio'
require 'fileutils'

@user = 'user'
@pass = 'password'
@host = 'http://localhost:1234'
@measure_dir = 'E:/openstudio-measures/NREL working measures'

def update_measures(measures_dir)
               
  json_request = JSON.generate({:measures_dir => measures_dir})
  request = RestClient::Resource.new("#{@host}/update_measures", user: @user, password: @pass)
  response = request.post(json_request, content_type: :json, accept: :json)
  
  result = []
  if response.code == 200
    result = JSON.parse(response.body, :symbolize_names => true)
  else
    raise response.body
  end
  
  return result
end


def compute_arguments(measure_dir, osm_path)
               
  json_request = JSON.generate({:measure_dir => measure_dir, :osm_path => osm_path})
  request = RestClient::Resource.new("#{@host}/compute_arguments", user: @user, password: @pass)
  response = request.post(json_request, content_type: :json, accept: :json)
  
  result = {}
  if response.code == 200
    result = JSON.parse(response.body, :symbolize_names => true)
  else
    raise response.body
  end
  
  return result
end

def create_measure(measure_dir, name, class_name, taxonomy_tag, measure_type, description, modeler_description)
               
  json_request = JSON.generate({:measure_dir => measure_dir, :name => name, :class_name => class_name, :taxonomy_tag => taxonomy_tag,:measure_type => measure_type, :description => description, :modeler_description => modeler_description})
  request = RestClient::Resource.new("#{@host}/create_measure", user: @user, password: @pass)
  response = request.post(json_request, content_type: :json, accept: :json)
  
  result = {}
  if response.code == 200
    result = JSON.parse(response.body, :symbolize_names => true)
  else
    raise response.body
  end
  
  return result
end

def duplicate_measure(old_measure_dir, measure_dir, name, class_name, taxonomy_tag, measure_type, description, modeler_description)
               
  json_request = JSON.generate({:old_measure_dir => old_measure_dir, :measure_dir => measure_dir, :name => name, :class_name => class_name, :taxonomy_tag => taxonomy_tag,:measure_type => measure_type, :description => description, :modeler_description => modeler_description})
  request = RestClient::Resource.new("#{@host}/duplicate_measure", user: @user, password: @pass)
  response = request.post(json_request, content_type: :json, accept: :json)
  
  result = {}
  if response.code == 200
    result = JSON.parse(response.body, :symbolize_names => true)
  else
    raise response.body
  end
  
  return result
end

if File.exist?('./output/')
  FileUtils.rm_rf('./output/')
end
FileUtils.mkdir_p('./output/')

osm_path = './output/model.osm'
model = OpenStudio::Model::exampleModel
model.save(osm_path, true)

measures = update_measures(@measure_dir)
puts measures

measures.each do |measure|
  info = compute_arguments(measure[:measure_dir], osm_path)
  puts info
end

measure_dir = './output/NewMeasure'
result = create_measure(measure_dir, "NewMeasure", "NewMeasure", "Envelope.Form", "ModelMeasure", "No description", "No modeler description")
puts result

new_measure_dir = './output/NewMeasureCopy'
result = duplicate_measure(measure_dir, new_measure_dir, "NewMeasureCopy", "NewMeasureCopy", "Envelope.Form", "ModelMeasure", "No description again", "No modeler description again")
puts result