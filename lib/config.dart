// import 'dart:io';
// import 'dart:typed_data';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:flutter_application_1/theme.dart';

// class SystemConfigurationPage extends StatefulWidget {
//   const SystemConfigurationPage({super.key});

//   @override
//   State<SystemConfigurationPage> createState() => _SystemConfigurationPageState();
// }

// class _SystemConfigurationPageState extends State<SystemConfigurationPage>
//     with SingleTickerProviderStateMixin {
//   late TabController _tabController;
//   final _formKey = GlobalKey<FormState>();

//   // Store Identity
//   final TextEditingController _companyNameController = TextEditingController();
//   final TextEditingController _storeIdController = TextEditingController();
//   final TextEditingController _legalEntityController = TextEditingController();
//   final TextEditingController _sloganController = TextEditingController();
//   String? _logoUrl;
//   File? _selectedLogoFile;
//   Uint8List? _selectedLogoBytes;

//   // Interface Theme
//   bool _isDarkMode = true;
//   bool _isCompactMode = false;
//   bool _isHighContrast = false;

//   // Contacts
//   List<Map<String, dynamic>> _contacts = [];

//   bool _isLoading = true;
//   bool _isSaving = false;
//   String? _configId;

//   @override
//   void initState() {
//     super.initState();
//     _tabController = TabController(length: 4, vsync: this);
//     _loadConfiguration();
//   }

//   @override
//   void dispose() {
//     _tabController.dispose();
//     _companyNameController.dispose();
//     _storeIdController.dispose();
//     _legalEntityController.dispose();
//     _sloganController.dispose();
//     super.dispose();
//   }

//   Future<void> _loadConfiguration() async {
//     try {
//       final snapshot = await FirebaseFirestore.instance
//           .collection('store')
//           .limit(1)
//           .get();

//       if (snapshot.docs.isNotEmpty) {
//         final doc = snapshot.docs.first;
//         final data = doc.data();
//         _configId = doc.id;

//         setState(() {
//           _companyNameController.text = data['companyName'] ?? '';
//           _storeIdController.text = data['storeId'] ?? '';
//           _legalEntityController.text = data['legalEntityName'] ?? '';
//           _sloganController.text = data['slogan'] ?? '';
//           _logoUrl = data['logoUrl'];
//           _isDarkMode = data['isDarkMode'] ?? true;
//           _isCompactMode = data['isCompactMode'] ?? false;
//           _isHighContrast = data['isHighContrast'] ?? false;
//           _contacts = List<Map<String, dynamic>>.from(data['contacts'] ?? []);
//           _isLoading = false;
//         });
//       } else {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       setState(() {
//         _isLoading = false;
//       });
//       _showSnackBar('Error loading configuration: $e', isError: true);
//     }
//   }

//   Future<void> _saveConfiguration() async {
//     if (!_formKey.currentState!.validate()) return;

//     setState(() {
//       _isSaving = true;
//     });

//     try {
//       String? uploadedLogoUrl = _logoUrl;

//       // Upload logo if a new one was selected
//       if (_selectedLogoBytes != null) {
//         final ref = FirebaseStorage.instance
//             .ref()
//             .child('store_logos')
//             .child('logo_${DateTime.now().millisecondsSinceEpoch}.png');
//         if (kIsWeb) {
//           await ref.putData(_selectedLogoBytes!);
//         } else if (_selectedLogoFile != null) {
//           await ref.putFile(_selectedLogoFile!);
//         }
//         uploadedLogoUrl = await ref.getDownloadURL();
//       }

//       final configData = {
//         'companyName': _companyNameController.text.trim(),
//         'storeId': _storeIdController.text.trim(),
//         'legalEntityName': _legalEntityController.text.trim(),
//         'slogan': _sloganController.text.trim(),
//         'logoUrl': uploadedLogoUrl,
//         'isDarkMode': _isDarkMode,
//         'isCompactMode': _isCompactMode,
//         'isHighContrast': _isHighContrast,
//         'contacts': _contacts,
//         'lastModified': FieldValue.serverTimestamp(),
//         'lastModifiedBy': 'Admin',
//       };

//       if (_configId != null) {
//         await FirebaseFirestore.instance
//             .collection('store')
//             .doc(_configId)
//             .update(configData);
//       } else {
//         final docRef = await FirebaseFirestore.instance
//             .collection('store')
//             .add(configData);
//         _configId = docRef.id;
//       }

//       _showSnackBar('Configuration saved successfully!');
//     } catch (e) {
//       _showSnackBar('Error saving configuration: $e', isError: true);
//     } finally {
//       setState(() {
//         _isSaving = false;
//       });
//     }
//   }

//   void _showSnackBar(String message, {bool isError = false}) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: isError ? Colors.red : accentGreen,
//       ),
//     );
//   }

//   Future<void> _pickLogo() async {
//     final picker = ImagePicker();
//     final pickedFile = await picker.pickImage(source: ImageSource.gallery);

//     if (pickedFile != null) {
//       final bytes = await pickedFile.readAsBytes();
//       setState(() {
//         _selectedLogoBytes = bytes;
//         if (!kIsWeb) {
//           _selectedLogoFile = File(pickedFile.path);
//         }
//       });
//     }
//   }

//   void _addContact() {
//     _showContactDialog();
//   }

//   void _editContact(int index) {
//     _showContactDialog(index: index, contact: _contacts[index]);
//   }

//   void _deleteContact(int index) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: bgMid,
//         title: const Text('Delete Contact', style: TextStyle(color: Colors.white)),
//         content: Text(
//           'Are you sure you want to delete ${_contacts[index]['name']}?',
//           style: const TextStyle(color: Colors.white70),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
//           ),
//           TextButton(
//             onPressed: () {
//               setState(() {
//                 _contacts.removeAt(index);
//               });
//               Navigator.pop(context);
//             },
//             child: const Text('Delete', style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showContactDialog({int? index, Map<String, dynamic>? contact}) {
//     final nameController = TextEditingController(text: contact?['name'] ?? '');
//     final roleController = TextEditingController(text: contact?['role'] ?? '');
//     final emailController = TextEditingController(text: contact?['email'] ?? '');
//     final phoneController = TextEditingController(text: contact?['phone'] ?? '');

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: bgMid,
//         title: Text(
//           index == null ? 'Add Contact' : 'Edit Contact',
//           style: const TextStyle(color: Colors.white),
//         ),
//         content: SingleChildScrollView(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               _buildDialogTextField('Name', nameController),
//               const SizedBox(height: 12),
//               _buildDialogTextField('Role', roleController),
//               const SizedBox(height: 12),
//               _buildDialogTextField('Email', emailController),
//               const SizedBox(height: 12),
//               _buildDialogTextField('Phone', phoneController),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
//           ),
//           TextButton(
//             onPressed: () {
//               if (nameController.text.isNotEmpty) {
//                 final newContact = {
//                   'name': nameController.text.trim(),
//                   'role': roleController.text.trim(),
//                   'email': emailController.text.trim(),
//                   'phone': phoneController.text.trim(),
//                 };

//                 setState(() {
//                   if (index != null) {
//                     _contacts[index] = newContact;
//                   } else {
//                     _contacts.add(newContact);
//                   }
//                 });
//                 Navigator.pop(context);
//               }
//             },
//             child: Text(
//               index == null ? 'Add' : 'Save',
//               style: const TextStyle(color: accentGreen),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDialogTextField(String label, TextEditingController controller) {
//     return TextField(
//       controller: controller,
//       style: const TextStyle(color: Colors.white),
//       decoration: InputDecoration(
//         labelText: label,
//         labelStyle: const TextStyle(color: Colors.white70),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: BorderSide(color: mutedGreen),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: accentGreen),
//         ),
//         filled: true,
//         fillColor: bgDark,
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: bgDark,
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator(color: accentGreen))
//           : Form(
//               key: _formKey,
//               child: Column(
//                 children: [
//                   _buildHeader(),
//                   _buildTabBar(),
//                   Expanded(
//                     child: TabBarView(
//                       controller: _tabController,
//                       children: [
//                         _buildGeneralTab(),
//                         _buildLocalizationTab(),
//                         _buildNotificationsTab(),
//                         _buildBackupDataTab(),
//                       ],
//                     ),
//                   ),
//                   _buildFooter(),
//                 ],
//               ),
//             ),
//     );
//   }

//   Widget _buildHeader() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//       color: bgDark,
//       child: Row(
//         children: [
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Text(
//                       'Configuration Hub',
//                       style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
//                     ),
//                     const Text(' > ', style: TextStyle(color: Colors.white38, fontSize: 12)),
//                     const Text(
//                       'General Settings',
//                       style: TextStyle(color: Colors.white70, fontSize: 12),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 const Text(
//                   'System Configuration',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 24,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           TextButton.icon(
//             onPressed: () {
//               // Show help dialog
//               showDialog(
//                 context: context,
//                 builder: (context) => AlertDialog(
//                   backgroundColor: bgMid,
//                   title: const Text('Help', style: TextStyle(color: Colors.white)),
//                   content: const Text(
//                     'Configure your store settings, theme preferences, and manage contact persons from this page.',
//                     style: TextStyle(color: Colors.white70),
//                   ),
//                   actions: [
//                     TextButton(
//                       onPressed: () => Navigator.pop(context),
//                       child: const Text('OK', style: TextStyle(color: accentGreen)),
//                     ),
//                   ],
//                 ),
//               );
//             },
//             icon: const Icon(Icons.help_outline, color: Colors.white70, size: 18),
//             label: const Text('Help', style: TextStyle(color: Colors.white70)),
//           ),
//           const SizedBox(width: 12),
//           ElevatedButton.icon(
//             onPressed: _isSaving ? null : _saveConfiguration,
//             style: ElevatedButton.styleFrom(
//               backgroundColor: accentGreen,
//               foregroundColor: bgDark,
//               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(8),
//               ),
//             ),
//             icon: _isSaving
//                 ? const SizedBox(
//                     width: 16,
//                     height: 16,
//                     child: CircularProgressIndicator(
//                       strokeWidth: 2,
//                       color: bgDark,
//                     ),
//                   )
//                 : const Icon(Icons.save, size: 18),
//             label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTabBar() {
//     return Container(
//       decoration: BoxDecoration(
//         color: bgDark,
//         border: Border(
//           bottom: BorderSide(color: mutedGreen, width: 1),
//         ),
//       ),
//       child: TabBar(
//         controller: _tabController,
//         isScrollable: true,
//         indicatorColor: accentGreen,
//         labelColor: accentGreen,
//         unselectedLabelColor: Colors.white70,
//         tabs: const [
//           Tab(
//             child: Row(
//               children: [
//                 Icon(Icons.tune, size: 16),
//                 SizedBox(width: 8),
//                 Text('General'),
//               ],
//             ),
//           ),
//           Tab(
//             child: Row(
//               children: [
//                 Icon(Icons.language, size: 16),
//                 SizedBox(width: 8),
//                 Text('Localization'),
//               ],
//             ),
//           ),
//           Tab(
//             child: Row(
//               children: [
//                 Icon(Icons.notifications_outlined, size: 16),
//                 SizedBox(width: 8),
//                 Text('Notifications'),
//               ],
//             ),
//           ),
//           Tab(
//             child: Row(
//               children: [
//                 Icon(Icons.backup_outlined, size: 16),
//                 SizedBox(width: 8),
//                 Text('Backup & Data'),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildGeneralTab() {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(24),
//       child: Column(
//         children: [
//           // Store Identity and Interface Theme Row
//           LayoutBuilder(
//             builder: (context, constraints) {
//               if (constraints.maxWidth > 900) {
//                 return Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Expanded(flex: 3, child: _buildStoreIdentitySection()),
//                     const SizedBox(width: 24),
//                     Expanded(flex: 2, child: _buildInterfaceThemeSection()),
//                   ],
//                 );
//               } else {
//                 return Column(
//                   children: [
//                     _buildStoreIdentitySection(),
//                     const SizedBox(height: 24),
//                     _buildInterfaceThemeSection(),
//                   ],
//                 );
//               }
//             },
//           ),
//           const SizedBox(height: 24),
//           _buildContactsSection(),
//         ],
//       ),
//     );
//   }

//   Widget _buildStoreIdentitySection() {
//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: bgMid,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: mutedGreen),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.all(8),
//                 decoration: BoxDecoration(
//                   color: mutedGreen,
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: const Icon(Icons.store, color: accentGreen, size: 20),
//               ),
//               const SizedBox(width: 12),
//               const Text(
//                 'Store Identity',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 24),
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Logo Upload
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Text(
//                     'Company Logo',
//                     style: TextStyle(color: Colors.white70, fontSize: 12),
//                   ),
//                   const SizedBox(height: 8),
//                   GestureDetector(
//                     onTap: _pickLogo,
//                     child: Container(
//                       width: 100,
//                       height: 100,
//                       decoration: BoxDecoration(
//                         color: bgDark,
//                         borderRadius: BorderRadius.circular(12),
//                         border: Border.all(color: mutedGreen, style: BorderStyle.solid),
//                       ),
//                       child: _selectedLogoBytes != null
//                           ? ClipRRect(
//                               borderRadius: BorderRadius.circular(12),
//                               child: Image.memory(
//                                 _selectedLogoBytes!,
//                                 fit: BoxFit.cover,
//                               ),
//                             )
//                           : _logoUrl != null
//                               ? ClipRRect(
//                                   borderRadius: BorderRadius.circular(12),
//                                   child: Image.network(
//                                     _logoUrl!,
//                                     fit: BoxFit.cover,
//                                     errorBuilder: (_, __, ___) => const Icon(
//                                       Icons.cloud_upload_outlined,
//                                       color: accentGreen,
//                                       size: 32,
//                                     ),
//                                   ),
//                                 )
//                               : const Column(
//                                   mainAxisAlignment: MainAxisAlignment.center,
//                                   children: [
//                                     Icon(
//                                       Icons.cloud_upload_outlined,
//                                       color: accentGreen,
//                                       size: 32,
//                                     ),
//                                     SizedBox(height: 4),
//                                     Text(
//                                       'Upload',
//                                       style: TextStyle(
//                                         color: accentGreen,
//                                         fontSize: 12,
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     'Max 2MB. PNG or SVG\npreferred.',
//                     style: TextStyle(
//                       color: Colors.white.withOpacity(0.4),
//                       fontSize: 10,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(width: 24),
//               // Form Fields
//               Expanded(
//                 child: Column(
//                   children: [
//                     Row(
//                       children: [
//                         Expanded(
//                           flex: 2,
//                           child: _buildTextField(
//                             label: 'Company Name',
//                             controller: _companyNameController,
//                             validator: (value) =>
//                                 value?.isEmpty == true ? 'Required' : null,
//                           ),
//                         ),
//                         const SizedBox(width: 16),
//                         Expanded(
//                           child: _buildTextField(
//                             label: 'Store ID',
//                             controller: _storeIdController,
//                             readOnly: true,
//                             hintText: 'Auto-generated',
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 16),
//                     _buildTextField(
//                       label: 'Legal Entity Name',
//                       controller: _legalEntityController,
//                     ),
//                     const SizedBox(height: 16),
//                     _buildTextField(
//                       label: 'Slogan / Tagline (Optional)',
//                       controller: _sloganController,
//                       hintText: 'e.g. Premium spirits for premium people',
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTextField({
//     required String label,
//     required TextEditingController controller,
//     String? hintText,
//     bool readOnly = false,
//     String? Function(String?)? validator,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           label,
//           style: const TextStyle(color: Colors.white70, fontSize: 12),
//         ),
//         const SizedBox(height: 8),
//         TextFormField(
//           controller: controller,
//           readOnly: readOnly,
//           validator: validator,
//           style: const TextStyle(color: Colors.white),
//           decoration: InputDecoration(
//             hintText: hintText,
//             hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
//             filled: true,
//             fillColor: bgDark,
//             contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
//             border: OutlineInputBorder(
//               borderRadius: BorderRadius.circular(8),
//               borderSide: BorderSide(color: mutedGreen),
//             ),
//             enabledBorder: OutlineInputBorder(
//               borderRadius: BorderRadius.circular(8),
//               borderSide: BorderSide(color: mutedGreen),
//             ),
//             focusedBorder: OutlineInputBorder(
//               borderRadius: BorderRadius.circular(8),
//               borderSide: const BorderSide(color: accentGreen),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildInterfaceThemeSection() {
//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: bgMid,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: mutedGreen),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.all(8),
//                 decoration: BoxDecoration(
//                   color: mutedGreen,
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: const Icon(Icons.palette_outlined, color: accentGreen, size: 20),
//               ),
//               const SizedBox(width: 12),
//               const Text(
//                 'Interface Theme',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 24),
//           const Text(
//             'System Mode',
//             style: TextStyle(color: Colors.white70, fontSize: 12),
//           ),
//           const SizedBox(height: 12),
//           Row(
//             children: [
//               _buildModeButton(
//                 icon: Icons.dark_mode,
//                 label: 'Dark',
//                 isSelected: _isDarkMode,
//                 onTap: () {
//                   setState(() => _isDarkMode = true);
//                   ThemeProvider().updateTheme(isDarkMode: true);
//                 },
//               ),
//               const SizedBox(width: 12),
//               _buildModeButton(
//                 icon: Icons.light_mode,
//                 label: 'Light',
//                 isSelected: !_isDarkMode,
//                 onTap: () {
//                   setState(() => _isDarkMode = false);
//                   ThemeProvider().updateTheme(isDarkMode: false);
//                 },
//               ),
//             ],
//           ),
//           const SizedBox(height: 24),
//           _buildToggleRow(
//             label: 'Compact Mode',
//             value: _isCompactMode,
//             onChanged: (val) {
//               setState(() => _isCompactMode = val);
//               ThemeProvider().updateTheme(isCompactMode: val);
//             },
//           ),
//           const SizedBox(height: 16),
//           _buildToggleRow(
//             label: 'High Contrast',
//             value: _isHighContrast,
//             onChanged: (val) {
//               setState(() => _isHighContrast = val);
//               ThemeProvider().updateTheme(isHighContrast: val);
//             },
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildModeButton({
//     required IconData icon,
//     required String label,
//     required bool isSelected,
//     required VoidCallback onTap,
//   }) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//         decoration: BoxDecoration(
//           color: isSelected ? mutedGreen : bgDark,
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: isSelected ? accentGreen : mutedGreen,
//             width: isSelected ? 2 : 1,
//           ),
//         ),
//         child: Column(
//           children: [
//             Icon(icon, color: isSelected ? accentGreen : Colors.white70, size: 24),
//             const SizedBox(height: 4),
//             Text(
//               label,
//               style: TextStyle(
//                 color: isSelected ? accentGreen : Colors.white70,
//                 fontSize: 12,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildToggleRow({
//     required String label,
//     required bool value,
//     required ValueChanged<bool> onChanged,
//   }) {
//     return Row(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: [
//         Text(
//           label,
//           style: const TextStyle(color: Colors.white, fontSize: 14),
//         ),
//         Switch(
//           value: value,
//           onChanged: onChanged,
//           activeColor: accentGreen,
//           activeTrackColor: mutedGreen,
//           inactiveThumbColor: Colors.white54,
//           inactiveTrackColor: bgDark,
//         ),
//       ],
//     );
//   }

//   Widget _buildContactsSection() {
//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: bgMid,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: mutedGreen),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Container(
//                 padding: const EdgeInsets.all(8),
//                 decoration: BoxDecoration(
//                   color: mutedGreen,
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: const Icon(Icons.contact_phone, color: accentGreen, size: 20),
//               ),
//               const SizedBox(width: 12),
//               const Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Key Contact Persons',
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 18,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                     SizedBox(height: 2),
//                     Text(
//                       'Manage authorized contacts for system alerts and billing.',
//                       style: TextStyle(color: Colors.white54, fontSize: 12),
//                     ),
//                   ],
//                 ),
//               ),
//               ElevatedButton.icon(
//                 onPressed: _addContact,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.transparent,
//                   foregroundColor: accentGreen,
//                   side: const BorderSide(color: accentGreen),
//                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                 ),
//                 icon: const Icon(Icons.add, size: 18),
//                 label: const Text('Add Contact'),
//               ),
//             ],
//           ),
//           const SizedBox(height: 24),
//           // Table Header
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//             decoration: BoxDecoration(
//               color: bgDark,
//               borderRadius: const BorderRadius.only(
//                 topLeft: Radius.circular(8),
//                 topRight: Radius.circular(8),
//               ),
//             ),
//             child: const Row(
//               children: [
//                 Expanded(
//                   flex: 2,
//                   child: Text(
//                     'NAME',
//                     style: TextStyle(
//                       color: Colors.white54,
//                       fontSize: 11,
//                       fontWeight: FontWeight.w600,
//                       letterSpacing: 1,
//                     ),
//                   ),
//                 ),
//                 Expanded(
//                   flex: 2,
//                   child: Text(
//                     'ROLE',
//                     style: TextStyle(
//                       color: Colors.white54,
//                       fontSize: 11,
//                       fontWeight: FontWeight.w600,
//                       letterSpacing: 1,
//                     ),
//                   ),
//                 ),
//                 Expanded(
//                   flex: 3,
//                   child: Text(
//                     'CONTACT INFO',
//                     style: TextStyle(
//                       color: Colors.white54,
//                       fontSize: 11,
//                       fontWeight: FontWeight.w600,
//                       letterSpacing: 1,
//                     ),
//                   ),
//                 ),
//                 SizedBox(
//                   width: 80,
//                   child: Text(
//                     'ACTIONS',
//                     style: TextStyle(
//                       color: Colors.white54,
//                       fontSize: 11,
//                       fontWeight: FontWeight.w600,
//                       letterSpacing: 1,
//                     ),
//                     textAlign: TextAlign.center,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           // Table Body
//           Container(
//             decoration: BoxDecoration(
//               border: Border.all(color: mutedGreen),
//               borderRadius: const BorderRadius.only(
//                 bottomLeft: Radius.circular(8),
//                 bottomRight: Radius.circular(8),
//               ),
//             ),
//             child: _contacts.isEmpty
//                 ? Padding(
//                     padding: const EdgeInsets.all(32),
//                     child: Center(
//                       child: Text(
//                         'No contacts added yet',
//                         style: TextStyle(color: Colors.white.withOpacity(0.5)),
//                       ),
//                     ),
//                   )
//                 : ListView.separated(
//                     shrinkWrap: true,
//                     physics: const NeverScrollableScrollPhysics(),
//                     itemCount: _contacts.length,
//                     separatorBuilder: (_, __) => Divider(color: mutedGreen, height: 1),
//                     itemBuilder: (context, index) {
//                       final contact = _contacts[index];
//                       return _buildContactRow(contact, index);
//                     },
//                   ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildContactRow(Map<String, dynamic> contact, int index) {
//     final name = contact['name'] ?? '';
//     final initials = name.isNotEmpty
//         ? name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
//         : '?';

//     // Generate a color based on the name
//     final colors = [
//       const Color(0xFF3B82F6),
//       const Color(0xFFF59E0B),
//       const Color(0xFF8B5CF6),
//       const Color(0xFFEC4899),
//       const Color(0xFF10B981),
//     ];
//     final colorIndex = name.hashCode % colors.length;

//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       child: Row(
//         children: [
//           Expanded(
//             flex: 2,
//             child: Row(
//               children: [
//                 Container(
//                   width: 36,
//                   height: 36,
//                   decoration: BoxDecoration(
//                     color: colors[colorIndex.abs()],
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Center(
//                     child: Text(
//                       initials,
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.w600,
//                         fontSize: 12,
//                       ),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Text(
//                     name,
//                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           Expanded(
//             flex: 2,
//             child: Text(
//               contact['role'] ?? '',
//               style: const TextStyle(color: Colors.white70),
//               overflow: TextOverflow.ellipsis,
//             ),
//           ),
//           Expanded(
//             flex: 3,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 if (contact['email']?.isNotEmpty == true)
//                   Row(
//                     children: [
//                       const Icon(Icons.email_outlined, size: 14, color: accentGreen),
//                       const SizedBox(width: 6),
//                       Expanded(
//                         child: Text(
//                           contact['email'],
//                           style: const TextStyle(color: Colors.white70, fontSize: 13),
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                     ],
//                   ),
//                 if (contact['phone']?.isNotEmpty == true) ...[
//                   const SizedBox(height: 4),
//                   Row(
//                     children: [
//                       const Icon(Icons.phone_outlined, size: 14, color: Colors.white54),
//                       const SizedBox(width: 6),
//                       Text(
//                         contact['phone'],
//                         style: const TextStyle(color: Colors.white54, fontSize: 13),
//                       ),
//                     ],
//                   ),
//                 ],
//               ],
//             ),
//           ),
//           SizedBox(
//             width: 80,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 IconButton(
//                   onPressed: () => _editContact(index),
//                   icon: const Icon(Icons.edit_outlined, size: 18),
//                   color: Colors.white54,
//                   splashRadius: 20,
//                 ),
//                 IconButton(
//                   onPressed: () => _deleteContact(index),
//                   icon: const Icon(Icons.delete_outline, size: 18),
//                   color: Colors.red.withOpacity(0.7),
//                   splashRadius: 20,
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildLocalizationTab() {
//     return const Center(
//       child: Text(
//         'Localization settings coming soon',
//         style: TextStyle(color: Colors.white54),
//       ),
//     );
//   }

//   Widget _buildNotificationsTab() {
//     return const Center(
//       child: Text(
//         'Notification settings coming soon',
//         style: TextStyle(color: Colors.white54),
//       ),
//     );
//   }

//   Widget _buildBackupDataTab() {
//     return const Center(
//       child: Text(
//         'Backup & Data settings coming soon',
//         style: TextStyle(color: Colors.white54),
//       ),
//     );
//   }

//   Widget _buildFooter() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//       decoration: BoxDecoration(
//         color: bgDark,
//         border: Border(
//           top: BorderSide(color: mutedGreen, width: 1),
//         ),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.end,
//         children: [
//           Text(
//             'Configuration ID: ${_configId ?? 'Not saved'} • Last modified by Admin',
//             style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
//           ),
//         ],
//       ),
//     );
//   }
// }
