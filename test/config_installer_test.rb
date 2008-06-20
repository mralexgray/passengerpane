require File.expand_path('../test_helper', __FILE__)
require 'config_installer'
require 'yaml'
require 'PassengerApplication'

describe "ConfigInstaller" do
  before do
    @tmp = File.expand_path('../tmp').bypass_safe_level_1
    FileUtils.mkdir_p @tmp
    @vhost_file = File.join(@tmp, 'test.vhost.conf')
    
    app = PassengerApplication.alloc.init
    app.stubs(:config_path).returns(@vhost_file)
    app.host = 'het-manfreds-blog.local'
    app.path = '/User/het-manfred/rails code/blog'
    app.environment = PassengerApplication::PRODUCTION
    app.allow_mod_rewrite = true
    app.vhostname = 'het-manfreds-wiki.local:443'
    
    @installer = ConfigInstaller.new([app.to_hash].to_yaml)
  end
  
  after do
    FileUtils.rm_rf @tmp
  end
  
  it "should initialize" do
    @installer.data.should == [{
      'config_path' => @vhost_file,
      'host' => 'het-manfreds-blog.local',
      'path' => '/User/het-manfred/rails code/blog',
      'environment' => 'production',
      'allow_mod_rewrite' => true,
      'base_uri' => '',
      'vhostname' => 'het-manfreds-wiki.local:443',
      'user_defined_data' => "  <directory \"/User/het-manfred/rails code/blog/public\">\n    Order allow,deny\n    Allow from all\n  </directory>"
    }]
  end
  
  it "should be able to add a new entry to the hosts" do
    @installer.expects(:system).with("/usr/bin/dscl localhost -create /Local/Default/Hosts/het-manfreds-blog.local IPAddress 127.0.0.1")
    @installer.add_to_hosts(0)
  end
  
  it "should check if the vhost directory exists, if not add it" do
    dir = "/private/etc/apache2/passenger_pane_vhosts"
    File.expects(:exist?).with(dir).returns(false)
    FileUtils.expects(:mkdir_p).with(dir)
    
    @installer.verify_vhost_conf
  end
  
  it "should check if our configuration to load the vhosts has been added to the apache conf yet" do
    conf = "/private/etc/apache2/httpd.conf"
    File.stubs(:read).with(conf).returns("Include /private/etc/apache2/other/*.conf")
    
    file_mock = mock("Apache conf")
    File.expects(:open).with(conf, 'a').yields(file_mock)
    file_mock.expects(:<<).with(%{

# Added by the Passenger preferences pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  Include /private/etc/apache2/passenger_pane_vhosts/*.conf
</IfModule>})

    @installer.verify_httpd_conf
  end
  
  it "should not add the vhosts configuration to the apache conf if it's in there already" do
    conf = "/private/etc/apache2/httpd.conf"
    File.stubs(:read).with(conf).returns(%{
Include /private/etc/apache2/other/*.conf

# Added by the Passenger preferences pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  Include /private/etc/apache2/passenger_pane_vhosts/*.conf
</IfModule>})
    
    File.expects(:open).times(0)
    @installer.verify_httpd_conf
  end
  
  it "should not check if our configuration to load the vhosts has been added to the apache conf yet" do
    conf = "/private/etc/apache2/httpd.conf"
    File.stubs(:read).with(conf).returns("Include /private/etc/apache2/other/*.conf")
    
    file_mock = mock("Apache conf")
    File.expects(:open).with(conf, 'a').yields(file_mock)
    file_mock.expects(:<<).with(%{

# Added by the Passenger preferences pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  Include /private/etc/apache2/passenger_pane_vhosts/*.conf
</IfModule>})
    
    @installer.verify_httpd_conf
  end
  
  it "should set the RailsBaseURI if there is one" do
    app_data = @installer.instance_variable_get(:@data)[0]
    app_data['new_app'] = false
    app_data['base_uri'] = '/rails/blog'
    app_data['vhostname'] = '*:80'
    app_data['user_defined_data'] = ''
    @installer.create_vhost_conf(0)
    
    File.read(@vhost_file.bypass_safe_level_1).should == %{
<VirtualHost *:80>
  ServerName het-manfreds-blog.local
  DocumentRoot "/User/het-manfred/rails code/blog/public"
  RailsEnv production
  RailsAllowModRewrite on
  RailsBaseURI /rails/blog
</VirtualHost>
}.sub(/^\n/, '')
  end
  
  it "should restart Apache" do
    @installer.expects(:system).with("/bin/launchctl stop org.apache.httpd")
    @installer.restart_apache!
  end
  
  it "should be able to take a serialized array of hashes and do all the work necessary in one go" do
    installer = ConfigInstaller.any_instance
    
    installer.expects(:verify_vhost_conf)
    installer.expects(:verify_httpd_conf)
    
    installer.expects(:add_to_hosts).with(0)
    installer.expects(:add_to_hosts).with(1)
    
    installer.expects(:create_vhost_conf).with(0)
    installer.expects(:create_vhost_conf).with(1)
    
    installer.expects(:restart_apache!)
    
    ConfigInstaller.new([{}, {}].to_yaml, 'extra command').install!
  end
end