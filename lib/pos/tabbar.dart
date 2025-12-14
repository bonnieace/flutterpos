import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter/material.dart';

import 'utils/device/device_utility.dart';
import 'utils/helpers/helper_functions.dart';

class TTabBar extends StatelessWidget implements PreferredSizeWidget{
  const TTabBar({super.key, required this.tabs});
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    final dark=THelperFunctions.isDarkMode(context);
    return Material(
      color: dark?TColors.black:TColors.white,
      child:  TabBar(
              isScrollable: true,
              indicatorColor: TColors.primary,
              labelColor: THelperFunctions.isDarkMode(context)?TColors.white:TColors.primary,
              unselectedLabelColor: TColors.darkGrey,
              tabs: tabs,
      
            
              )
              ,
    );
  }
  
  @override
  // TODO: implement preferredSize

 Size get preferredSize => Size.fromHeight(TDeviceUtils.getAppBarHeight());
}