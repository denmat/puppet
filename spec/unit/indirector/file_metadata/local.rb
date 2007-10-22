#!/usr/bin/env ruby
#
#  Created by Luke Kanies on 2007-10-18.
#  Copyright (c) 2007. All rights reserved.

require File.dirname(__FILE__) + '/../../../spec_helper'

require 'puppet/indirector/file_metadata/local'

describe Puppet::Indirector::FileMetadata::Local do
    it "should be registered with the file_metadata indirection" do
        Puppet::Indirector::Terminus.terminus_class(:file_metadata, :local).should equal(Puppet::Indirector::FileMetadata::Local)
    end
end

describe Puppet::Indirector::FileMetadata::Local, "when finding a single file" do
    before do
        @content = Puppet::Indirector::FileMetadata::Local.new
        @uri = "file:///my/local"

        @data = mock 'metadata'
    end
    it "should return a Metadata instance created with the full path to the file if the file exists" do
        @data.stubs(:get_attributes)

        FileTest.expects(:exists?).with("/my/local").returns true
        Puppet::FileServing::Metadata.expects(:new).with("/my/local").returns(@data)
        @content.find(@uri).should == @data
    end

    it "should collect its attributes when a file is found" do
        @data.expects(:get_attributes)

        FileTest.expects(:exists?).with("/my/local").returns true
        Puppet::FileServing::Metadata.expects(:new).with("/my/local").returns(@data)
        @content.find(@uri).should == @data
    end

    it "should return nil if the file does not exist" do
        FileTest.expects(:exists?).with("/my/local").returns false
        @content.find(@uri).should be_nil
    end
end