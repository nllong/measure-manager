require 'rubygems'

require 'net/http'
require 'json'
require 'openstudio'
require 'fileutils'

@user = 'user'
@pass = 'password'
@host = 'http://localhost:1234'
@host = '127.0.0.1'
@port = '1234'


def load_osm(osm_path)

  path = "/load_osm"
  payload ={
    :osm_path => osm_path
  }.to_json
  
  req = Net::HTTP::Post.new(path, initheader = {'Content-Type' =>'application/json'})
  req.basic_auth @user, @pass
  req.body = payload
  response = Net::HTTP.new(@host, @port).start {|http| http.request(req) }
  puts "Response #{response.code} #{response.message}:\n #{response.body}"
end

def create_measure(measure_path, name, class_name, taxonomy_tag, measure_type, description, modeler_description)
               
  path = "/create_measure"
  payload ={
    :measure_path => measure_path,
    :name => name, 
    :class_name => class_name, 
    :taxonomy_tag => taxonomy_tag,
    :measure_type => measure_type, 
    :description => description, 
    :modeler_description => modeler_description
  }.to_json
  
  req = Net::HTTP::Post.new(path, initheader = {'Content-Type' =>'application/json'})
  req.basic_auth @user, @pass
  req.body = payload
  response = Net::HTTP.new(@host, @port).start {|http| http.request(req) }
  puts "Response #{response.code} #{response.message}:\n #{response.body}"
end

def compute_arguments(measure_path, osm_path)
               
  path = "/compute_arguments"
  payload ={
    :measure_path => measure_path,
    :osm_path => osm_path
  }.to_json
  
  req = Net::HTTP::Post.new(path, initheader = {'Content-Type' =>'application/json'})
  req.basic_auth @user, @pass
  req.body = payload
  response = Net::HTTP.new(@host, @port).start {|http| http.request(req) }
  puts "Response #{response.code} #{response.message}:\n #{response.body}"
end

if File.exist?('./output/')
  FileUtils.rm_rf('./output/')
end
FileUtils.mkdir_p('./output/')

model = OpenStudio::Model::exampleModel
model.save('./output/model.osm', true)

load_osm('./output/model.osm')

create_measure('./output/new_measure/', 'New Measure', 'NewMeasure', 'None.None', 'ModelMeasure', 'Description', 'Modeler Description')

compute_arguments('./output/new_measure/', './output/model.osm')
compute_arguments('./output/new_measure/', './output/model.osm')
compute_arguments('./output/new_measure/', './output/model.osm')
compute_arguments('./output/new_measure/', './output/model.osm')