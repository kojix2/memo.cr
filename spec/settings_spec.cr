require "./spec_helper"

describe Memo::Settings do
  it "reads existing settings and persists a change across instances" do
    with_store do |_, root|
      path = File.join(root, "settings.json")
      File.write(path, %({"version":1,"ui":{"editor_font_size_px":20},"future":true}))
      settings = Memo::Settings.new(path)
      settings.editor_font_size_px.should eq(20)
      settings.sidebar_width_px.should eq(280)
      settings.update_editor_font_size_px(24)
      Memo::Settings.new(path).editor_font_size_px.should eq(24)
      Memo::Settings::Data.from_json(File.read(path + ".bak")).ui.editor_font_size_px.should eq(20)
      Dir.glob(path + ".tmp.*").should be_empty
    end
  end

  it "persists sidebar width without losing font settings and rejects invalid widths" do
    with_store do |_, root|
      path = File.join(root, "settings.json")
      settings = Memo::Settings.new(path)
      settings.update_editor_font_size_px(20)
      settings.update_sidebar_width_px(360)
      settings.update_editor_font_size_px(24)
      [149, 601].each do |width|
        expect_raises(ArgumentError) { settings.update_sidebar_width_px(width) }
      end
      restored = Memo::Settings.new(path)
      restored.sidebar_width_px.should eq(360)
      restored.editor_font_size_px.should eq(24)
    end
  end

  it "rejects out-of-range font sizes without overwriting saved settings" do
    with_store do |_, root|
      path = File.join(root, "settings.json")
      settings = Memo::Settings.new(path)
      settings.update_editor_font_size_px(18)
      [9, 33].each do |size|
        expect_raises(ArgumentError) { settings.update_editor_font_size_px(size) }
      end
      Memo::Settings.new(path).editor_font_size_px.should eq(18)
    end
  end

  it "quarantines corrupt JSON and normalizes unsupported values" do
    with_store do |_, root|
      path = File.join(root, "settings.json")
      File.write(path, "{broken")
      Memo::Settings.new(path).editor_font_size_px.should eq(16)
      Dir.glob(path + ".corrupt.*").size.should eq(1)
      File.write(path, %({"version":99,"ui":{"editor_font_size_px":999,"sidebar_width_px":999}}))
      data = Memo::Settings.new(path).load
      data.version.should eq(1)
      data.ui.editor_font_size_px.should eq(16)
      data.ui.sidebar_width_px.should eq(280)
    end
  end
end
