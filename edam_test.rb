require 'bundler/inline'
require 'bundler'

gemfile(true, {ui: Bundler::UI::Silent.new }) do
  source 'https://rubygems.org'

  gem "evernote-thrift"
  gem "pry"
end

require "digest/md5"
require 'evernote-thrift'

class ENClient
  EVERNOTE_HOST = "www.evernote.com"

  def auth_token
    @auth_token ||= File.read(File.expand_path "~/secrets/evernote-personal-auth-token").strip
  end

  def user_store
    @user_store ||=
      begin
        userStoreUrl = "https://#{EVERNOTE_HOST}/edam/user"
        userStoreTransport = Thrift::HTTPClientTransport.new(userStoreUrl)
        userStoreProtocol = Thrift::BinaryProtocol.new(userStoreTransport)
        Evernote::EDAM::UserStore::UserStore::Client.new(userStoreProtocol)
      end
  end

  def check_version!
    versionOK = user_store.checkVersion("Evernote EDAMTest (Ruby)",
      Evernote::EDAM::UserStore::EDAM_VERSION_MAJOR,
      Evernote::EDAM::UserStore::EDAM_VERSION_MINOR)

    if !versionOK
      $stderr.puts "Version error"
      exit(1)
    end
  end

  def initialize
    check_version!
  end

  def note_store()
    @note_store ||=
      begin
        # Get the URL used to interact with the contents of the user's account
        # When your application authenticates using OAuth, the NoteStore URL will
        # be returned along with the auth token in the final OAuth request.
        # In that case, you don't need to make this call.
        # binding.pry
        noteStoreUrl = user_store.getNoteStoreUrl(auth_token)

        noteStoreTransport = Thrift::HTTPClientTransport.new(noteStoreUrl)
        noteStoreProtocol = Thrift::BinaryProtocol.new(noteStoreTransport)
        Evernote::EDAM::NoteStore::NoteStore::Client.new(noteStoreProtocol)
      end
  end

  def do_test
    list_notebooks
    make_test_note
  end

  def agenda
    display_notebook_and_notes("Actions")
    display_notebook_and_notes("Projects")
  end


  def display_notebook_and_notes(notebook_name)
    actions_nb = notebooks.find { |x| x.name == notebook_name}

    puts notebook_name

    filter = Evernote::EDAM::NoteStore::NoteFilter.new(notebookGuid: actions_nb.guid)
    result_spec = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new(includeTitle: true)
    results = note_store.findNotesMetadata(auth_token, filter, 0, 500, result_spec)

    results.notes.each do |note|
      puts "- #{note.title}"
    end
  end


  def notebooks
    note_store.listNotebooks(auth_token)
  end

  def list_notebooks
    # List all of the notebooks in the user's account
    nbs = note_store.listNotebooks(auth_token)
    puts "Found #{nbs.size} notebooks:"
    nbs.each do |notebook|
      puts "  * #{notebook.name}"
    end
  end

  def make_test_note
    # To create a new note, simply create a new Note object and fill in
    # attributes such as the note's title.
    note = Evernote::EDAM::Type::Note.new
    note.title = "Test note from EDAMTest.rb"

    # To include an attachment such as an image in a note, first create a Resource
    # for the attachment. At a minimum, the Resource contains the binary attachment
    # data, an MD5 hash of the binary data, and the attachment MIME type. It can also
    #/ include attributes such as filename and location.
    filename = "enlogo.png"
    image = File.open(filename, "rb") { |io| io.read }
    hashFunc = Digest::MD5.new

    data = Evernote::EDAM::Type::Data.new
    data.size = image.size
    data.bodyHash = hashFunc.digest(image)
    data.body = image

    resource = Evernote::EDAM::Type::Resource.new
    resource.mime = "image/png"
    resource.data = data
    resource.attributes = Evernote::EDAM::Type::ResourceAttributes.new
    resource.attributes.fileName = filename

    # Now, add the new Resource to the note's list of resources
    note.resources = [ resource ]

    # To display the Resource as part of the note's content, include an <en-media>
    # tag in the note's ENML content. The en-media tag identifies the corresponding
    # Resource using the MD5 hash.
    hashHex = hashFunc.hexdigest(image)

    # The content of an Evernote note is represented using Evernote Markup Language
    # (ENML). The full ENML specification can be found in the Evernote API Overview
    # at http://dev.evernote.com/documentation/cloud/chapters/ENML.php
    note.content = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note>Here is the Evernote logo:<br/>
  <en-media type="image/png" hash="#{hashHex}"/>
</en-note>
EOF

    # Finally, send the new note to Evernote using the createNote method
    # The new Note object that is returned will contain server-generated
    # attributes such as the new note's unique GUID.
    createdNote = note_store.createNote(auth_token, note)

    puts "Successfully created a new note with GUID: #{createdNote.guid}"
  end
end


ENClient.new.agenda
