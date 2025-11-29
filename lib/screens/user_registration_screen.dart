import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/snackbar_helper.dart';

class UserRegistrationScreen extends StatefulWidget {
  final String? existingName;
  final String? existingImagePath;
  final bool isEditMode;

  const UserRegistrationScreen({
    super.key,
    this.existingName,
    this.existingImagePath,
    this.isEditMode = false,
  });

  @override
  State<UserRegistrationScreen> createState() => _UserRegistrationScreenState();
}

class _UserRegistrationScreenState extends State<UserRegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;

  static const Color bgWhite = Colors.white;
  static const Color bgGrey = Color(0xFFF6F7F8);
  static const Color primaryBlue = Color(0xFF3A91FF);
  static const Color textDark = Color(0xFF2D3142);
  static const Color textGrey = Color(0xFF949BA5);
  static const Color inputFill = Color(0xFFF0F2F5);

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _nameController.text = widget.existingName ?? '';
      if (widget.existingImagePath != null) {
        _imageFile = XFile(widget.existingImagePath!);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _imageFile = image);
      }
    } catch (e) {
      showAppSnackBar(context, '접근 권한이 필요합니다', type: AppSnackType.error);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                _buildImageOption(Icons.camera_alt_rounded, 'Camera', () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                }),
                _buildImageOption(Icons.photo_library_rounded, 'Gallery', () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                }),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageOption(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 30),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primaryBlue, size: 24),
            ),
            const SizedBox(width: 20),
            Text(
              label,
              style: const TextStyle(
                color: textDark,
                fontSize: 16,
                fontFamily: 'Sen',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleRegister() {
    if (_imageFile == null) {
      showAppSnackBar(context, '프로필 사진을 등록해주세요', type: AppSnackType.error);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      showAppSnackBar(context, '이름을 입력해주세요', type: AppSnackType.error);
      return;
    }

    Navigator.pop(context, {
      'action': 'register',
      'name': _nameController.text.trim(),
      'imagePath': _imageFile!.path,
    });
  }

  void _handleDelete() {
    if (!widget.isEditMode) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete User', style: TextStyle(fontFamily: 'Sen', fontWeight: FontWeight.bold, color: textDark)),
        content: const Text('이 사용자를 정말 삭제하시겠습니까?', style: TextStyle(fontFamily: 'Sen', color: textGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Sen', color: textGrey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, {'action': 'delete'});
            },
            child: const Text('Delete', style: TextStyle(fontFamily: 'Sen', color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      appBar: AppBar(
        backgroundColor: bgWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isEditMode ? 'Edit Profile' : 'New Profile',
          style: const TextStyle(
            color: textDark,
            fontFamily: 'Sen',
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 30),

              // 1. Image Picker Area
              Center(
                child: GestureDetector(
                  onTap: _showImageSourceDialog,
                  child: Stack(
                    children: [
                      // 이미지 원형 컨테이너
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: inputFill,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: primaryBlue.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: _imageFile == null
                            ? const Icon(Icons.person_rounded, size: 60, color: Color(0xFFC4C9D3))
                            : ClipOval(
                          child: Image.file(
                            File(_imageFile!.path),
                            fit: BoxFit.cover,
                            width: 140,
                            height: 140,
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: textDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      "Display Name",
                      style: TextStyle(
                        fontFamily: 'Sen',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: inputFill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        fontFamily: 'Sen',
                        fontSize: 16,
                        color: textDark,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: "Enter user name",
                        hintStyle: TextStyle(
                          fontFamily: 'Sen',
                          color: textGrey.withOpacity(0.7),
                        ),
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: textGrey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 50),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    elevation: 4,
                    shadowColor: primaryBlue.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "Save Profile",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (widget.isEditMode)
                TextButton(
                  onPressed: _handleDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[400],
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red[400]),
                      const SizedBox(width: 8),
                      const Text(
                        "Delete User",
                        style: TextStyle(
                          fontFamily: 'Sen',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}