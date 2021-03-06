#! /usr/bin/env ruby
require 'spec_helper'

describe Puppet::Parser do

  Puppet::Parser::AST

  before :each do
    @known_resource_types = Puppet::Resource::TypeCollection.new("development")
    @parser = Puppet::Parser::Parser.new "development"
    @parser.stubs(:known_resource_types).returns @known_resource_types
    @true_ast = Puppet::Parser::AST::Boolean.new :value => true
  end

  it "should require an environment at initialization" do
    expect {
      Puppet::Parser::Parser.new
    }.to raise_error(ArgumentError, /wrong number of arguments/)
  end

  it "should set the environment" do
    env = Puppet::Node::Environment.new
    Puppet::Parser::Parser.new(env).environment.should == env
  end

  it "should convert the environment into an environment instance if a string is provided" do
    env = Puppet::Node::Environment.new("testing")
    Puppet::Parser::Parser.new("testing").environment.should == env
  end

  it "should be able to look up the environment-specific resource type collection" do
    rtc = Puppet::Node::Environment.new("development").known_resource_types
    parser = Puppet::Parser::Parser.new "development"
    parser.known_resource_types.should equal(rtc)
  end

  context "when importing" do
    it "should delegate importing to the known resource type loader" do
      parser = Puppet::Parser::Parser.new "development"
      parser.known_resource_types.loader.expects(:import).with("newfile", "current_file")
      parser.lexer.expects(:file).returns "current_file"
      parser.import("newfile")
    end

    it "should import multiple files on one line" do
      @parser.known_resource_types.loader.expects(:import).with('one', nil)
      @parser.known_resource_types.loader.expects(:import).with('two', nil)
      @parser.parse("import 'one', 'two'")
    end
  end

  describe "when parsing files" do
    before do
      FileTest.stubs(:exist?).returns true
      File.stubs(:read).returns ""
      @parser.stubs(:watch_file)
    end

    it "should treat files ending in 'rb' as ruby files" do
      @parser.expects(:parse_ruby_file)
      @parser.file = "/my/file.rb"
      @parser.parse
    end
  end

  describe "when parsing append operator" do

    it "should not raise syntax errors" do
      expect { @parser.parse("$var += something") }.to_not raise_error
    end

    it "should raise syntax error on incomplete syntax " do
      expect {
        @parser.parse("$var += ")
      }.to raise_error(Puppet::ParseError, /Syntax error at end of file/)
    end

    it "should create ast::VarDef with append=true" do
      vardef = @parser.parse("$var += 2").code[0]
      vardef.should be_a(Puppet::Parser::AST::VarDef)
      vardef.append.should == true
    end

    it "should work with arrays too" do
      vardef = @parser.parse("$var += ['test']").code[0]
      vardef.should be_a(Puppet::Parser::AST::VarDef)
      vardef.append.should == true
    end

  end

  describe "when parsing selector" do
    it "should support hash access on the left hand side" do
      expect { @parser.parse("$h = { 'a' => 'b' } $a = $h['a'] ? { 'b' => 'd', default => undef }") }.to_not raise_error
    end
  end

  describe "parsing 'unless'" do
    it "should create the correct ast objects" do
      Puppet::Parser::AST::Not.expects(:new).with { |h| h[:value].is_a?(Puppet::Parser::AST::Boolean) }
      @parser.parse("unless false { $var = 1 }")
    end
    
    it "should not raise an error with empty statements" do
      expect { @parser.parse("unless false { }") }.to_not raise_error
    end
    
    #test for bug #13296
    it "should not override 'unless' as a parameter inside resources" do
      lambda { @parser.parse("exec {'/bin/echo foo': unless => '/usr/bin/false',}") }.should_not raise_error
    end
  end

  describe "when parsing parameter names" do
    Puppet::Parser::Lexer::KEYWORDS.sort_tokens.each do |keyword|
      it "should allow #{keyword} as a keyword" do
        lambda { @parser.parse("exec {'/bin/echo foo': #{keyword} => '/usr/bin/false',}") }.should_not raise_error
      end
    end
  end

  describe "when parsing 'if'" do
    it "not, it should create the correct ast objects" do
      Puppet::Parser::AST::Not.expects(:new).with { |h| h[:value].is_a?(Puppet::Parser::AST::Boolean) }
      @parser.parse("if ! true { $var = 1 }")
    end

    it "boolean operation, it should create the correct ast objects" do
      Puppet::Parser::AST::BooleanOperator.expects(:new).with {
        |h| h[:rval].is_a?(Puppet::Parser::AST::Boolean) and h[:lval].is_a?(Puppet::Parser::AST::Boolean) and h[:operator]=="or"
      }
      @parser.parse("if true or true { $var = 1 }")

    end

    it "comparison operation, it should create the correct ast objects" do
      Puppet::Parser::AST::ComparisonOperator.expects(:new).with {
        |h| h[:lval].is_a?(Puppet::Parser::AST::Name) and h[:rval].is_a?(Puppet::Parser::AST::Name) and h[:operator]=="<"
      }
      @parser.parse("if 1 < 2 { $var = 1 }")

    end

  end

  describe "when parsing if complex expressions" do
    it "should create a correct ast tree" do
      aststub = stub_everything 'ast'
      Puppet::Parser::AST::ComparisonOperator.expects(:new).with {
        |h| h[:rval].is_a?(Puppet::Parser::AST::Name) and h[:lval].is_a?(Puppet::Parser::AST::Name) and h[:operator]==">"
      }.returns(aststub)
      Puppet::Parser::AST::ComparisonOperator.expects(:new).with {
        |h| h[:rval].is_a?(Puppet::Parser::AST::Name) and h[:lval].is_a?(Puppet::Parser::AST::Name) and h[:operator]=="=="
      }.returns(aststub)
      Puppet::Parser::AST::BooleanOperator.expects(:new).with {
        |h| h[:rval]==aststub and h[:lval]==aststub and h[:operator]=="and"
      }
      @parser.parse("if (1 > 2) and (1 == 2) { $var = 1 }")
    end

    it "should raise an error on incorrect expression" do
      expect {
        @parser.parse("if (1 > 2 > ) or (1 == 2) { $var = 1 }")
      }.to raise_error(Puppet::ParseError, /Syntax error at '\)'/)
    end

  end

  describe "when parsing resource references" do

    it "should not raise syntax errors" do
      expect { @parser.parse('exec { test: param => File["a"] }') }.to_not raise_error
    end

    it "should not raise syntax errors with multiple references" do
      expect { @parser.parse('exec { test: param => File["a","b"] }') }.to_not raise_error
    end

    it "should create an ast::ResourceReference" do
      Puppet::Parser::AST::ResourceReference.expects(:new).with { |arg|
        arg[:line]==1 and arg[:type]=="File" and arg[:title].is_a?(Puppet::Parser::AST::ASTArray)
      }
      @parser.parse('exec { test: command => File["a","b"] }')
    end
  end

  describe "when parsing resource overrides" do

    it "should not raise syntax errors" do
      expect { @parser.parse('Resource["title"] { param => value }') }.to_not raise_error
    end

    it "should not raise syntax errors with multiple overrides" do
      expect { @parser.parse('Resource["title1","title2"] { param => value }') }.to_not raise_error
    end

    it "should create an ast::ResourceOverride" do
      #Puppet::Parser::AST::ResourceOverride.expects(:new).with { |arg|
      #  arg[:line]==1 and arg[:object].is_a?(Puppet::Parser::AST::ResourceReference) and arg[:parameters].is_a?(Puppet::Parser::AST::ResourceParam)
      #}
      ro = @parser.parse('Resource["title1","title2"] { param => value }').code[0]
      ro.should be_a(Puppet::Parser::AST::ResourceOverride)
      ro.line.should == 1
      ro.object.should be_a(Puppet::Parser::AST::ResourceReference)
      ro.parameters[0].should be_a(Puppet::Parser::AST::ResourceParam)
    end

  end

  describe "when parsing if statements" do

    it "should not raise errors with empty if" do
      expect { @parser.parse("if true { }") }.to_not raise_error
    end

    it "should not raise errors with empty else" do
      expect { @parser.parse("if false { notice('if') } else { }") }.to_not raise_error
    end

    it "should not raise errors with empty if and else" do
      expect { @parser.parse("if false { } else { }") }.to_not raise_error
    end

    it "should create a nop node for empty branch" do
      Puppet::Parser::AST::Nop.expects(:new)
      @parser.parse("if true { }")
    end

    it "should create a nop node for empty else branch" do
      Puppet::Parser::AST::Nop.expects(:new)
      @parser.parse("if true { notice('test') } else { }")
    end

    it "should build a chain of 'ifs' if there's an 'elsif'" do
      expect { @parser.parse(<<-PP) }.to_not raise_error
        if true { notice('test') } elsif true {} else { }
      PP
    end

  end

  describe "when parsing function calls" do
    it "should not raise errors with no arguments" do
      expect { @parser.parse("tag()") }.to_not raise_error
    end

    it "should not raise errors with rvalue function with no args" do
      expect { @parser.parse("$a = template()") }.to_not raise_error
    end

    it "should not raise errors with arguments" do
      expect { @parser.parse("notice(1)") }.to_not raise_error
    end

    it "should not raise errors with multiple arguments" do
      expect { @parser.parse("notice(1,2)") }.to_not raise_error
    end

    it "should not raise errors with multiple arguments and a trailing comma" do
      expect { @parser.parse("notice(1,2,)") }.to_not raise_error
    end

  end

  describe "when parsing arrays" do
    it "should parse an array" do
      expect { @parser.parse("$a = [1,2]") }.to_not raise_error
    end

    it "should not raise errors with a trailing comma" do
      expect { @parser.parse("$a = [1,2,]") }.to_not raise_error
    end

    it "should accept an empty array" do
      expect { @parser.parse("$var = []\n") }.to_not raise_error
    end
  end

  describe "when providing AST context" do
    before do
      @lexer = stub 'lexer', :line => 50, :file => "/foo/bar", :getcomment => "whev"
      @parser.stubs(:lexer).returns @lexer
    end

    it "should include the lexer's line" do
      @parser.ast_context[:line].should == 50
    end

    it "should include the lexer's file" do
      @parser.ast_context[:file].should == "/foo/bar"
    end

    it "should include the docs if directed to do so" do
      @parser.ast_context(true)[:doc].should == "whev"
    end

    it "should not include the docs when told not to" do
      @parser.ast_context(false)[:doc].should be_nil
    end

    it "should not include the docs by default" do
      @parser.ast_context[:doc].should be_nil
    end
  end

  describe "when building ast nodes" do
    before do
      @lexer = stub 'lexer', :line => 50, :file => "/foo/bar", :getcomment => "whev"
      @parser.stubs(:lexer).returns @lexer
      @class = Puppet::Resource::Type.new(:hostclass, "myclass", :use_docs => false)
    end

    it "should return a new instance of the provided class created with the provided options" do
      @class.expects(:new).with { |opts| opts[:foo] == "bar" }
      @parser.ast(@class, :foo => "bar")
    end

    it "should merge the ast context into the provided options" do
      @class.expects(:new).with { |opts| opts[:file] == "/foo" }
      @parser.expects(:ast_context).returns :file => "/foo"
      @parser.ast(@class, :foo => "bar")
    end

    it "should prefer provided options over AST context" do
      @class.expects(:new).with { |opts| opts[:file] == "/bar" }
      @lexer.expects(:file).returns "/foo"
      @parser.ast(@class, :file => "/bar")
    end

    it "should include docs when the AST class uses them" do
      @class.expects(:use_docs).returns true
      @class.stubs(:new)
      @parser.expects(:ast_context).with{ |docs, line| docs == true }.returns({})
      @parser.ast(@class, :file => "/bar")
    end

    it "should get docs from lexer using the correct AST line number" do
      @class.expects(:use_docs).returns true
      @class.stubs(:new).with{ |a| a[:doc] == "doc" }
      @lexer.expects(:getcomment).with(12).returns "doc"
      @parser.ast(@class, :file => "/bar", :line => 12)
    end
  end

  describe "when retrieving a specific node" do
    it "should delegate to the known_resource_types node" do
      @known_resource_types.expects(:node).with("node")

      @parser.node("node")
    end
  end

  describe "when retrieving a specific class" do
    it "should delegate to the loaded code" do
      @known_resource_types.expects(:hostclass).with("class")

      @parser.hostclass("class")
    end
  end

  describe "when retrieving a specific definitions" do
    it "should delegate to the loaded code" do
      @known_resource_types.expects(:definition).with("define")

      @parser.definition("define")
    end
  end

  describe "when determining the configuration version" do
    it "should determine it from the resource type collection" do
      @parser.known_resource_types.expects(:version).returns "foo"
      @parser.version.should == "foo"
    end
  end

  describe "when looking up definitions" do
    it "should use the known resource types to check for them by name" do
      @parser.known_resource_types.stubs(:find_or_load).with("namespace","name",:definition).returns(:this_value)
      @parser.find_definition("namespace","name").should == :this_value
    end
  end

  describe "when looking up hostclasses" do
    it "should use the known resource types to check for them by name" do
      @parser.known_resource_types.stubs(:find_or_load).with("namespace","name",:hostclass,{}).returns(:this_value)
      @parser.find_hostclass("namespace","name").should == :this_value
    end
  end

  describe "when parsing classes" do
    before :each do
      @krt = Puppet::Resource::TypeCollection.new("development")
      @parser = Puppet::Parser::Parser.new "development"
      @parser.stubs(:known_resource_types).returns @krt
    end

    it "should not create new classes" do
      @parser.parse("class foobar {}").code[0].should be_a(Puppet::Parser::AST::Hostclass)
      @krt.hostclass("foobar").should be_nil
    end

    it "should correctly set the parent class when one is provided" do
      @parser.parse("class foobar inherits yayness {}").code[0].instantiate('')[0].parent.should == "yayness"
    end

    it "should correctly set the parent class for multiple classes at a time" do
      statements = @parser.parse("class foobar inherits yayness {}\nclass boo inherits bar {}").code
      statements[0].instantiate('')[0].parent.should == "yayness"
      statements[1].instantiate('')[0].parent.should == "bar"
    end

    it "should define the code when some is provided" do
      @parser.parse("class foobar { $var = val }").code[0].code.should_not be_nil
    end

    it "should accept parameters with trailing comma" do
      @parser.parse("file { '/example': ensure => file, }").should be
    end

    it "should accept parametrized classes with trailing comma" do
      @parser.parse("class foobar ($var1 = 0,) { $var = val }").code[0].code.should_not be_nil
    end

    it "should define parameters when provided" do
      foobar = @parser.parse("class foobar($biz,$baz) {}").code[0].instantiate('')[0]
      foobar.arguments.should == {"biz" => nil, "baz" => nil}
    end
  end

  describe "when parsing resources" do
    before :each do
      @krt = Puppet::Resource::TypeCollection.new("development")
      @parser = Puppet::Parser::Parser.new "development"
      @parser.stubs(:known_resource_types).returns @krt
    end

    it "should be able to parse class resources" do
      @krt.add(Puppet::Resource::Type.new(:hostclass, "foobar", :arguments => {"biz" => nil}))
      expect { @parser.parse("class { foobar: biz => stuff }") }.to_not raise_error
    end

    it "should correctly mark exported resources as exported" do
      @parser.parse("@@file { '/file': }").code[0].exported.should be_true
    end

    it "should correctly mark virtual resources as virtual" do
      @parser.parse("@file { '/file': }").code[0].virtual.should be_true
    end
  end

  describe "when parsing nodes" do
    it "should be able to parse a node with a single name" do
      node = @parser.parse("node foo { }").code[0]
      node.should be_a Puppet::Parser::AST::Node
      node.names.length.should == 1
      node.names[0].value.should == "foo"
    end

    it "should be able to parse a node with two names" do
      node = @parser.parse("node foo, bar { }").code[0]
      node.should be_a Puppet::Parser::AST::Node
      node.names.length.should == 2
      node.names[0].value.should == "foo"
      node.names[1].value.should == "bar"
    end

    it "should be able to parse a node with three names" do
      node = @parser.parse("node foo, bar, baz { }").code[0]
      node.should be_a Puppet::Parser::AST::Node
      node.names.length.should == 3
      node.names[0].value.should == "foo"
      node.names[1].value.should == "bar"
      node.names[2].value.should == "baz"
    end
  end

  it "should fail if trying to collect defaults" do
    expect {
      @parser.parse("@Port { protocols => tcp }")
    }.to raise_error(Puppet::ParseError, /Defaults are not virtualizable/)
  end

  context "when parsing collections" do
    it "should parse basic collections" do
      @parser.parse("Port <| |>").code.
        should be_all {|x| x.is_a? Puppet::Parser::AST::Collection }
    end

    it "should parse fully qualified collections" do
      @parser.parse("Port::Range <| |>").code.
        should be_all {|x| x.is_a? Puppet::Parser::AST::Collection }
    end
  end

  it "should not assign to a fully qualified variable" do
    expect {
      @parser.parse("$one::two = yay")
    }.to raise_error(Puppet::ParseError, /Cannot assign to variables in other namespaces/)
  end

  it "should parse assignment of undef" do
    tree = @parser.parse("$var = undef")
    tree.code.children[0].should be_an_instance_of Puppet::Parser::AST::VarDef
    tree.code.children[0].value.should be_an_instance_of Puppet::Parser::AST::Undef
  end

  context "#namesplit" do
    { "base::sub" => %w{base sub},
      "main" => ["", "main"],
      "one::two::three::four" => ["one::two::three", "four"],
    }.each do |input, output|
      it "should split #{input.inspect} to #{output.inspect}" do
        @parser.namesplit(input).should == output
      end
    end
  end

  it "should treat classes as case insensitive" do
    @parser.known_resource_types.import_ast(@parser.parse("class yayness {}"), '')
    @parser.known_resource_types.hostclass('yayness').
      should == @parser.find_hostclass("", "YayNess")
  end

  it "should treat defines as case insensitive" do
    @parser.known_resource_types.import_ast(@parser.parse("define funtest {}"), '')
    @parser.known_resource_types.hostclass('funtest').
      should == @parser.find_hostclass("", "fUntEst")
  end
end
