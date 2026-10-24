extends Control

@onready var input_type: OptionButton = %InputType
@onready var text_input: TextEdit = %TextInput
@onready var error_label: Label = %ErrorLabel
@onready var size_slider: HSlider = %SizeSlider
@onready var size_value_lbl: Label = %SizeValueLbl
@onready var border_slider: HSlider = %BorderSlider
@onready var border_val_lbl: Label = %BorderValLbl
@onready var ec_option: OptionButton = %ECOption
@onready var fg_picker: ColorPickerButton = %FGPicker
@onready var bg_picker: ColorPickerButton = %BGPicker
@onready var qr_display: TextureRect = %QRDisplay
@onready var download_btn: Button = %DownloadBtn
@onready var copy_btn: Button = %CopyBtn
@onready var file_dialog: FileDialog = %FileDialog

var current_image: Image = null
var formatted_payload: String = ""

enum TypeEnum { URL, TEXT, EMAIL, PHONE }

func _ready() -> void:
	_setup_ui_elements()
	_connect_events()
	_validate_input()

func _setup_ui_elements() -> void:
	input_type.clear()
	input_type.add_item("Website URL", TypeEnum.URL)
	input_type.add_item("Plain Text", TypeEnum.TEXT)
	input_type.add_item("Email Address", TypeEnum.EMAIL)
	input_type.add_item("Phone Number", TypeEnum.PHONE)
	
	ec_option.clear()
	ec_option.add_item("Low (7%)", QREngine.ECLevel.LOW)
	ec_option.add_item("Medium (15%)", QREngine.ECLevel.MEDIUM)
	ec_option.add_item("Quartile (25%)", QREngine.ECLevel.QUARTILE)
	ec_option.add_item("High (30%)", QREngine.ECLevel.HIGH)
	ec_option.select(1)
	
	fg_picker.color = Color.BLACK
	bg_picker.color = Color.WHITE
	
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG Files"])

func _connect_events() -> void:
	text_input.text_changed.connect(_validate_input)
	input_type.item_selected.connect(func(_idx): _validate_input())
	ec_option.item_selected.connect(func(_idx): _regenerate_qr())
	
	size_slider.value_changed.connect(func(v):
		size_value_lbl.text = str(int(v)) + " px"
		_regenerate_qr()
	)
	
	border_slider.value_changed.connect(func(v):
		border_val_lbl.text = str(int(v)) + " modules"
		_regenerate_qr()
	)
	
	fg_picker.color_changed.connect(func(_c): _check_contrast_and_render())
	bg_picker.color_changed.connect(func(_c): _check_contrast_and_render())
	
	download_btn.pressed.connect(_on_download_pressed)
	copy_btn.pressed.connect(_on_copy_pressed)
	file_dialog.file_selected.connect(_save_file_to_disk)

func _validate_input() -> void:
	var raw := text_input.text.strip_edges()
	var selected_type: TypeEnum = input_type.get_selected_id() as TypeEnum
	var is_valid := false
	var err_msg := ""
	
	if raw.is_empty():
		err_msg = "Please enter data to encode."
	else:
		match selected_type:
			TypeEnum.URL:
				if raw.begins_with("http://") or raw.begins_with("https://"):
					is_valid = true
					formatted_payload = raw
				elif raw.contains("."):
					is_valid = true
					formatted_payload = "https://" + raw
				else:
					err_msg = "Invalid URL format (e.g., https://example.com)"

			TypeEnum.TEXT:
				is_valid = true
				formatted_payload = raw

			TypeEnum.EMAIL:
				var regex := RegEx.new()
				regex.compile("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$")
				if regex.search(raw):
					is_valid = true
					formatted_payload = "mailto:" + raw
				else:
					err_msg = "Invalid email syntax"

			TypeEnum.PHONE:
				var regex := RegEx.new()
				regex.compile("^\\+?[0-9\\s\\-\\(\\)]{7,20}$")
				if regex.search(raw):
					is_valid = true
					formatted_payload = "tel:" + raw
				else:
					err_msg = "Invalid phone format"

	if is_valid:
		error_label.text = "Input is valid"
		error_label.modulate = Color.GREEN
		download_btn.disabled = false
		copy_btn.disabled = false
		_check_contrast_and_render()
	else:
		error_label.text = err_msg
		error_label.modulate = Color.RED
		download_btn.disabled = true
		copy_btn.disabled = true

func _check_contrast_and_render() -> void:
	var fg := fg_picker.color
	var bg := bg_picker.color
	var dist := Vector3(fg.r, fg.g, fg.b).distance_to(Vector3(bg.r, bg.g, bg.b))
	
	if dist < 0.4:
		error_label.text = "Warning: Low color contrast may fail scanning!"
		error_label.modulate = Color.ORANGE
	
	_regenerate_qr()

func _regenerate_qr() -> void:
	if formatted_payload.is_empty() or download_btn.disabled:
		return
		
	var px := int(size_slider.value)
	var quiet := int(border_slider.value)
	var ec: QREngine.ECLevel = ec_option.get_selected_id() as QREngine.ECLevel
	
	current_image = QREngine.generate_qr(
		formatted_payload,
		px,
		fg_picker.color,
		bg_picker.color,
		quiet,
		ec
	)
	
	qr_display.texture = ImageTexture.create_from_image(current_image)

func _on_download_pressed() -> void:
	if current_image == null: return
	
	if OS.get_name() == "Web":
		var buffer := current_image.save_png_to_buffer()
		JavaScriptBridge.download_buffer(buffer, "qrcode.png", "image/png")
	else:
		file_dialog.popup_centered(Vector2i(650, 450))

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(formatted_payload)
	error_label.text = "Copied raw payload to clipboard!"
	error_label.modulate = Color.CYAN

func _save_file_to_disk(path: String) -> void:
	if current_image != null:
		current_image.save_png(path)
