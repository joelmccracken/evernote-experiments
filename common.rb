require 'bundler/inline'
require 'bundler'

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

  def handle_inbox_links(doc, note)
    doc.css('a').each do |link|
      handle_inbox_link(link, doc, note)
    end
  end

  def handle_inbox_link(link, doc, note)
    while true
      puts link.to_xml
      puts "what do with link? (o)pen, view (f)ull note, re(m)ove, (r)efile, (q)uit"
      response = gets.strip
      # response = "r"
      case response
      when "m" then
        link.remove
        update_note_doc(note, doc)
        return :handled
      when "r" then
        do_refile_flow(link, doc, note)
      when "o" then
        `open #{link[:href]}`
      when "f" then
        open_note_browser(doc)
      when "q" then
        exit 0
      end
    end
  end

  def do_refile_flow(link, src_doc, src_note)
    display_refile_targets

    loop do
      puts "commands: enter number to refile, go (b)ack"
      input = gets.strip
      # input = "13"
      if input == "b"
        return :back
      else
        begin
          num = Integer(input)
          target = refile_targets[num]
          if target.nil?
            puts "no choice with that number"
          else
            puts "refiling into #{target.title}"
            puts "additional note:"
            additional_note = gets.strip
            # additional_note = ""

            # get target to refile to
            note2 = get_full_note_by_guid(target.guid)
            target_doc = Oga.parse_xml(note2.content)
            body = target_doc.css('en-note').first

            # make a new hr element
            hr_element = Oga.parse_xml("<hr>").css("hr").first

            # append hr element and link, first remove link
            body.children << hr_element
            link.remove

            if additional_note.length > 0
              additional_note_element = Oga.parse_xml("<div>#{additional_note}</div>").css("div").first
              body.children << additional_note_element
            end

            body.children << link

            # save changed note
            update_note_doc(note2, target_doc)

            update_note_doc(src_note, src_doc)
            return :success
          end
        rescue ArgumentError
          puts "not recognized command"
        end
      end

      # case input
      # when "n" then
      #   results = process_refile
      #   case results
      #   when :success then return :success
      #   when :error then return :error
      #   end
      # when "b" then
      #   return :go_back
      # end
    end
  end

  def update_note(note)
    note_store.updateNote(auth_token, note)
  end

  def update_note_doc(note, doc)
    note.content = doc.to_xml
    update_note(note)
  end

  def display_refile_targets
    refile_targets.each do |number, note|
      puts "#{number}. #{note.title}"
    end
  end


  def refile_targets()
    @refile_targets ||=
      begin
        refile_tag = tags.find{ |t| t.name == "refile-targets"}
        filter = Evernote::EDAM::NoteStore::NoteFilter.new(tagGuids: [refile_tag.guid])
        metadata_result_spec = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new(includeTitle: true)
        targets = note_store.findNotesMetadata(auth_token, filter, 0, 500, metadata_result_spec)
        targets.notes.each_with_index.map {|note, i|  [i, note]}.to_h
      end
  end

  def open_note_browser(note_doc)
    tf = Tempfile.new(["note", ".html"])
    tf.puts note_doc.to_xml
    tf.close
    `open #{tf.path}`
  end

  def inbox_notes
    inbox_nb = notebooks.find { |x| x.name == "_Inbox"}

    filter = Evernote::EDAM::NoteStore::NoteFilter.new(notebookGuid: inbox_nb.guid)
    metadata_result_spec = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new(includeTitle: true)

    results = note_store.findNotesMetadata(auth_token, filter, 0, 500, metadata_result_spec)

    results.notes
  end

  def inbox
    inbox_notes.each do |note|
      puts "Note: #{note.title}"
      puts "what do you want to do? (s)kip, (q)uit, (p)ry, (d)ig"
      input = gets.strip
      # input = "d"
      case input
      when "d" then
        note2 = get_full_note_by_guid(note.guid)
        doc = Oga.parse_xml(note2.content)
        handle_inbox_links(doc, note2)
      when "p" then
        note2 = get_full_note_by_guid(note.guid)
        doc = Oga.parse_xml(note2.content)
        binding.pry
      when "s" then
        puts "skipping..."
      when "q" then
        puts "quitting.."
        exit 0
      else
        puts "not recognized, nuttin happening"
      end
    end
  end

  def get_full_note_by_guid(guid)
    note_store.getNote(auth_token, guid, true, true, true, true)
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

  def tags
    note_store.listTags(auth_token)
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
