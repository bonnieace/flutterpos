// import 'package:flutter_application_1/pos/goods.dart';
// import 'package:flutter_application_1/pos/inv.dart';
// import 'package:flutter_application_1/pos/pos.dart';
// import 'package:flutter_application_1/pos/reports.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:iconsax/iconsax.dart';

// import '../constants/colors.dart';


// class NavigationMenu extends StatelessWidget {
//   const NavigationMenu({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final controller = Get.put(NavigationController());
//     return Scaffold(
// bottomNavigationBar: Obx(
//   ()=>NavigationBar(
//     height: 80,
//     elevation: 0,
//     selectedIndex: controller.selectedIndex.value,
//     onDestinationSelected: (index)=>controller.selectedIndex.value=index,
//     backgroundColor:Colors.transparent,
//     indicatorColor:TColors.black.withOpacity(0.1),
//     destinations: const [
//     NavigationDestination(icon: Icon(Iconsax.shop), label: ' Shop'),
//     NavigationDestination(icon: Icon(Iconsax.archive4), label: 'Products'),
//     NavigationDestination(icon: Icon(Iconsax.box_add), label: 'updates'),
//     NavigationDestination(icon: Icon(Iconsax.receipt), label: 'Reports'),

  
  
  
  
  
    
//   ]),
// ),
// body:Obx(()=> controller.screens[controller.selectedIndex.value]),

//     );
//   }
// }

// class NavigationController extends GetxController{
//   final Rx<int> selectedIndex=0.obs;
//   final screens=[const pos(), const goods(),const inv(),const Reports()

//   ];

// }