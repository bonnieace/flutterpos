import 'package:Thamani/constants/colors.dart';
import 'package:Thamani/pos/reports/debtpayment.dart';
import 'package:Thamani/pos/reports/productreport.dart';
import 'package:Thamani/pos/reports/salesReports.dart';
import 'package:Thamani/pos/tabbar.dart';
import 'package:flutter/material.dart';

import '../constants/sizes.dart';
import 'reports/monthlyreports.dart';
import 'reports/paymentsfreq.dart';
import 'reports/profits.dart';
import 'utils/helpers/helper_functions.dart';

class Reports extends StatelessWidget {
  const Reports({super.key});

  @override
  Widget build(BuildContext context) {
    final dark=THelperFunctions.isDarkMode(context);
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        
      /*  appBar: TappBar(
          title: Text('store',style: Theme.of(context).textTheme.headlineMedium,),
          actions: [
            cartcountdown(onPressed: (){}, iconColor: dark?Colors.white: Colors.black)
          ],
        
      
      
        ),*/
       body: NestedScrollView(headerSliverBuilder:(_,innerBoxIsSrollable){
        return [
          const SliverAppBar(
            shadowColor: TColors.white,
            automaticallyImplyLeading: false,
            pinned: true,
            floating: true,
          // backgroundColor: THelperFunctions.isDarkMode(context)?  TColors.black:TColors.white,
            //expandedHeight: 440,
            flexibleSpace: Padding(padding: EdgeInsets.all(TSizes.defaultSpace),
            child:

            TTabBar(
              
              tabs: 
              
              
              [
              Tab(child: Text('Profits')),

              Tab(child: Text('Daily Sales')),
              Tab(child: Text('Debt')),
              Tab(child: Text('Payment Records')),
              Tab(child: Text('Monthly Sales')),
              Tab(child: Text('Products Report')),
])
          )),
        ];
       } 
      
       , body:  const TabBarView(children: [
                ProfitReportsPage(),

        SalesReportPage(),
        DebtPaymentsPage(),
        PaymentFrequencyPage(),
        MonthlySalesReportPage(),
        ProductSalesReportPage(),




       ],)),
       
       
      
        
      ),
    );
  }
}


