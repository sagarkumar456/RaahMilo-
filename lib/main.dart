import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';

const blue = Color(0xff0866ef);
const navy = Color(0xff0d2351);
const tile = Color(0xfff3f6fb);
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TrackerApp());
}
class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'TrackMyPhone', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3:true, colorScheme: ColorScheme.fromSeed(seedColor: blue),
      scaffoldBackgroundColor: Colors.white, appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: navy),
      inputDecorationTheme: InputDecorationTheme(filled:true, fillColor: tile, border: OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor:blue,foregroundColor:Colors.white,minimumSize:const Size.fromHeight(52),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))))),
    home: StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(),builder:(context,snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body:Center(child:CircularProgressIndicator()));
      return snapshot.data == null ? const WelcomeScreen() : const HomeShell();
    }),
  );
}
class BrandSplashScreen extends StatelessWidget {
 const BrandSplashScreen({super.key});
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:navy,body:SafeArea(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
   const Icon(Icons.location_on_rounded,color:Colors.white,size:105),
   const SizedBox(height:18),const Text('TrackMyPhone',style:TextStyle(color:Colors.white,fontSize:32,fontWeight:FontWeight.bold)),
   const SizedBox(height:8),const Text('Your Phone, Your GPS Tracker',style:TextStyle(color:Colors.white70)),
   const SizedBox(height:45),ElevatedButton(onPressed:()=>Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const WelcomeScreen())),child:const Text('Continue'))
 ]))));
}
class PermissionExplainerScreen extends StatelessWidget {
 const PermissionExplainerScreen({super.key});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Location Permission')),body:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   const Spacer(),const Icon(Icons.my_location,size:105,color:blue),const SizedBox(height:25),
   const Text('Your location stays under your control',textAlign:TextAlign.center,style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:navy)),
   const SizedBox(height:18),const Text('We use precise location only after you start a trip to show your live position and draw your route. Only viewers you approve can see a shared trip.',textAlign:TextAlign.center),
   const SizedBox(height:18),const ListTile(leading:Icon(Icons.place,color:blue),title:Text('Live GPS coordinates')),
   const ListTile(leading:Icon(Icons.route,color:blue),title:Text('Save route history')),
   const ListTile(leading:Icon(Icons.stop_circle,color:blue),title:Text('Stop tracking whenever you want')),
   const Spacer(),ElevatedButton(onPressed:()async{try{if(!await Geolocator.isLocationServiceEnabled())throw Exception('Enable Location in Settings');var status=await Geolocator.checkPermission();if(status==LocationPermission.denied)status=await Geolocator.requestPermission();if(!context.mounted)return;if(status==LocationPermission.deniedForever||status==LocationPermission.denied)throw Exception('Permission not granted');Navigator.pop(context);}catch(e){if(context.mounted)showMsg(context,'$e');}},child:const Text('Allow Location Access')),
   TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Maybe later'))
 ])));
}
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(26),child: Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    const Spacer(),const Icon(Icons.location_on_rounded,size:95,color:blue),const SizedBox(height:28),const Text('Turn Your Phone into a GPS Tracker',textAlign:TextAlign.center,style:TextStyle(fontSize:30,fontWeight:FontWeight.bold,color:navy)),
    const SizedBox(height:14),const Text('Live location, route history, and controlled sharing. Your location is shared only when you choose.',textAlign:TextAlign.center),const Spacer(),
    ElevatedButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AuthScreen())),child:const Text('Get Started')),
    const SizedBox(height:12),const Text('Your tracking is always under your control',style:TextStyle(color:Colors.grey))
  ]))));
}
class AuthScreen extends StatefulWidget { const AuthScreen({super.key}); @override State<AuthScreen> createState()=>_AuthScreenState(); }
class _AuthScreenState extends State<AuthScreen> {
  final email=TextEditingController(),password=TextEditingController(), name=TextEditingController();
  bool register=false,loading=false;
  @override void dispose(){email.dispose();password.dispose();name.dispose();super.dispose();}
  Future<void> submit() async {
    if(email.text.trim().isEmpty||password.text.isEmpty){showMsg(context,'Enter email and password');return;}
    setState(()=>loading=true);
    try {
      if(register){ final c=await FirebaseAuth.instance.createUserWithEmailAndPassword(email:email.text.trim(),password:password.text); if(name.text.trim().isNotEmpty) await c.user?.updateDisplayName(name.text.trim()); }
      else {await FirebaseAuth.instance.signInWithEmailAndPassword(email:email.text.trim(),password:password.text);}
      if(mounted) Navigator.of(context).popUntil((r)=>r.isFirst);
    } on FirebaseAuthException catch(e){if(mounted)showMsg(context,e.message??e.code);}
    catch(e){if(mounted)showMsg(context,'Login failed: $e');}
    finally {if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(),body:SingleChildScrollView(padding:const EdgeInsets.all(25),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const SizedBox(height:45),const Icon(Icons.pin_drop,size:64,color:blue),const SizedBox(height:18),Text(register?'Create Account':'Welcome Back',style:const TextStyle(fontSize:29,fontWeight:FontWeight.bold,color:navy)),
    const SizedBox(height:8),Text(register?'Start GPS tracking securely':'Login to continue tracking',style:const TextStyle(color:Colors.grey)),const SizedBox(height:30),
    if(register)...[TextField(controller:name,decoration:const InputDecoration(labelText:'Full name',prefixIcon:Icon(Icons.person_outline))),const SizedBox(height:12)],
    TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email address',prefixIcon:Icon(Icons.email_outlined))),const SizedBox(height:12),
    TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password',prefixIcon:Icon(Icons.lock_outline))),
    const SizedBox(height:20),ElevatedButton(onPressed:loading?null:submit,child:Text(loading?'Please wait…':register?'Sign Up':'Login')),
    if(!register)TextButton(onPressed:()async{if(email.text.trim().isEmpty){showMsg(context,'Enter your email first');return;}try{await FirebaseAuth.instance.sendPasswordResetEmail(email:email.text.trim());if(context.mounted)showMsg(context,'Password reset email sent');}catch(e){if(context.mounted)showMsg(context,'Unable to send email: $e');}},child:const Text('Forgot password?')),
    TextButton(onPressed:()=>setState(()=>register=!register),child:Text(register?'Already have an account? Login':'No account? Sign up')),
  ])));
}
void showMsg(BuildContext context,String message){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}

class TrackingController extends ChangeNotifier {
  final db=FirebaseFirestore.instance;
  StreamSubscription<Position>? subscription;
  final List<LatLng> points=[];
  Position? current;
  String? tripId;
  bool active=false,starting=false;
  double meters=0;
  DateTime? began;
  String? lastError;
  Future<void> start() async {
    if(active||starting)return;
    starting=true;notifyListeners();
    try {
      if(!await Geolocator.isLocationServiceEnabled())throw Exception('Enable location services in your phone settings.');
      var permission=await Geolocator.checkPermission();
      if(permission==LocationPermission.denied) permission=await Geolocator.requestPermission();
      if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw Exception('Location permission required.');
      final uid=FirebaseAuth.instance.currentUser!.uid;
      began=DateTime.now(); meters=0;points.clear();current=null;
      final ref=await db.collection('trips').add({'ownerId':uid,'viewerIds':<String>[],'startedAt':FieldValue.serverTimestamp(),'endedAt':null,'active':true,'distanceMeters':0.0,'latest':null});
      tripId=ref.id;active=true;notifyListeners();
      const settings=LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:5);
      subscription=Geolocator.getPositionStream(locationSettings:settings).listen((p)=>_onPosition(p),onError:(Object e){lastError=e.toString();notifyListeners();});
    } catch(e){lastError='$e'; if(tripId!=null&&active){await stop();}rethrow;}
    finally{starting=false;notifyListeners();}
  }
  Future<void> _onPosition(Position p) async {
    if(!active||tripId==null)return;
    if(p.accuracy>100)return; // Reject very inaccurate fixes.
    final old=current;
    if(old!=null){final step=Geolocator.distanceBetween(old.latitude,old.longitude,p.latitude,p.longitude);
      if(step<3)return; if(step>500 && p.timestamp.difference(old.timestamp).inSeconds<10)return;
      meters+=step;
    }
    current=p;points.add(LatLng(p.latitude,p.longitude));notifyListeners();
    final id=tripId!;
    try {
      final ref=db.collection('trips').doc(id);
      await ref.collection('points').add({'lat':p.latitude,'lng':p.longitude,'accuracy':p.accuracy,'speed':p.speed,'at':Timestamp.fromDate(p.timestamp)});
      await ref.update({'latest':{'lat':p.latitude,'lng':p.longitude,'speed':p.speed,'accuracy':p.accuracy,'at':Timestamp.fromDate(p.timestamp)},'distanceMeters':meters});
    }catch(e){lastError='Upload failed: $e';notifyListeners();}
  }
  Future<void> stop() async {
    active=false;notifyListeners();await subscription?.cancel();subscription=null;
    final id=tripId;tripId=null;
    if(id!=null)await db.collection('trips').doc(id).update({'active':false,'endedAt':FieldValue.serverTimestamp(),'distanceMeters':meters});
    notifyListeners();
  }
  @override void dispose(){subscription?.cancel();super.dispose();}
}
final tracker=TrackingController();
class HomeShell extends StatefulWidget {const HomeShell({super.key});@override State<HomeShell> createState()=>_HomeShellState();}
class _HomeShellState extends State<HomeShell>{int tab=0;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('TrackMyPhone',style:TextStyle(fontWeight:FontWeight.bold,color:navy)),actions:[IconButton(icon:const Icon(Icons.notifications_none),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const NotificationsScreen())))]),
    body:IndexedStack(index:tab,children:[Dashboard(onTab:(n)=>setState(()=>tab=n)),const LiveMapScreen(),const HistoryScreen(),const ProfileScreen()]),
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(n)=>setState(()=>tab=n),destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.map_outlined),label:'Map'),NavigationDestination(icon:Icon(Icons.history),label:'History'),NavigationDestination(icon:Icon(Icons.person_outline),label:'Profile')]),
  );
}
class Dashboard extends StatelessWidget {final ValueChanged<int> onTab; const Dashboard({super.key,required this.onTab});
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:tracker,builder:(context,_)=>ListView(padding:const EdgeInsets.all(18),children:[
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:tile,borderRadius:BorderRadius.circular(18)),child:Row(children:[CircleAvatar(backgroundColor:tracker.active?Colors.green.shade100:Colors.grey.shade200,child:Icon(Icons.gps_fixed,color:tracker.active?Colors.green:Colors.grey)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(tracker.active?'Tracking active':'Tracking stopped',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Text(tracker.active?'Location is being shared with approved viewers':'Tap Start to record a route',style:const TextStyle(fontSize:12))])),
    if(tracker.active)TextButton(onPressed:()=>tracker.stop(),child:const Text('Stop',style:TextStyle(color:Colors.red)))])),
    const SizedBox(height:12),TextButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PermissionExplainerScreen())),icon:const Icon(Icons.security),label:const Text('How location permissions work')),
    const SizedBox(height:14),GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:1.28,children:[
      _Quick(icon:Icons.navigation,color:Colors.blue,label:'Live Tracking',action:()=>onTab(1)),
      _Quick(icon:Icons.route,color:Colors.purple,label:'Trip History',action:()=>onTab(2)),
      _Quick(icon:Icons.share_location,color:Colors.green,label:'Share Trip',action:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ShareScreen()))),
      _Quick(icon:Icons.radar,color:Colors.orange,label:'Geofence',action:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const GeofenceScreen()))),
    ]),const SizedBox(height:20),ElevatedButton.icon(onPressed:tracker.starting?null:()async{if(tracker.active){await tracker.stop();}else {try {await tracker.start();}catch(e){if(context.mounted)showMsg(context,'$e');}}},icon:Icon(tracker.active?Icons.stop_circle:Icons.play_arrow),label:Text(tracker.active?'Stop Tracking':'Start Tracking')),
    if(tracker.lastError!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(tracker.lastError!,style:const TextStyle(color:Colors.red,fontSize:12))),
    const SizedBox(height:14),const Text('Location is collected only after you start tracking. Keep the app open for this version.',style:TextStyle(fontSize:12,color:Colors.grey)),
  ]));
}
class _Quick extends StatelessWidget {final IconData icon;final Color color;final String label;final VoidCallback action;const _Quick({required this.icon,required this.color,required this.label,required this.action});
  @override Widget build(BuildContext context)=>InkWell(onTap:action,borderRadius:BorderRadius.circular(17),child:Container(decoration:BoxDecoration(color:tile,borderRadius:BorderRadius.circular(17)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[CircleAvatar(backgroundColor:color.withValues(alpha:.12),child:Icon(icon,color:color)),const SizedBox(height:10),Text(label,style:const TextStyle(fontWeight:FontWeight.w700))])));
}
const startPlace=LatLng(28.6139,77.2090); // Only used as an initial map viewport, not real tracking data.
class LiveMapScreen extends StatelessWidget {const LiveMapScreen({super.key});
 @override Widget build(BuildContext context)=>AnimatedBuilder(animation:tracker,builder:(context,_) {final position=tracker.current;final currentPoint=position==null?null:LatLng(position.latitude,position.longitude);
  return Stack(children:[GoogleMap(initialCameraPosition:CameraPosition(target:currentPoint??startPlace,zoom:15),myLocationEnabled:false,myLocationButtonEnabled:false,
    markers:currentPoint==null?{}:{Marker(markerId:const MarkerId('device'),position:currentPoint,infoWindow:const InfoWindow(title:'Your device'))},
    polylines:{if(tracker.points.length>1)Polyline(polylineId:const PolylineId('route'),points:tracker.points,width:6,color:blue)}),
    Positioned(bottom:16,left:14,right:14,child:Card(elevation:6,child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[Icon(Icons.circle,color:tracker.active?Colors.green:Colors.grey,size:12),const SizedBox(width:8),Text(tracker.active?'Live Tracking':'Not tracking',style:const TextStyle(fontWeight:FontWeight.bold)),const Spacer(),Text('${((position?.speed??0).clamp(0,999)*3.6).toStringAsFixed(1)} km/h')]),
      const SizedBox(height:10),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('Lat: ${position?.latitude.toStringAsFixed(6)??"—"}'),Text('Lng: ${position?.longitude.toStringAsFixed(6)??"—"}')]),
      const SizedBox(height:8),Text('Distance: ${(tracker.meters/1000).toStringAsFixed(2)} km   •   Accuracy: ${position?.accuracy.toStringAsFixed(0)??"—"} m'),
      TextButton.icon(onPressed:()=>showModalBottomSheet(context:context,showDragHandle:true,builder:(_)=>TrackingDetailsSheet(position:position)),icon:const Icon(Icons.info_outline),label:const Text('Tracking Details')),
      const SizedBox(height:8),
      ElevatedButton(onPressed:tracker.starting?null:()async{try{if(tracker.active){await tracker.stop();}else{await tracker.start();}}catch(e){if(context.mounted)showMsg(context,'$e');}},child:Text(tracker.active?'Stop Tracking':'Start Tracking'))
    ])))));
 });
}
class TrackingDetailsSheet extends StatelessWidget {
 final Position? position;
 const TrackingDetailsSheet({super.key,required this.position});
 @override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   const Text('Tracking Details',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:12),
   ListTile(leading:const Icon(Icons.location_on),title:const Text('Latitude'),trailing:Text(position?.latitude.toStringAsFixed(6)??'—')),
   ListTile(leading:const Icon(Icons.place),title:const Text('Longitude'),trailing:Text(position?.longitude.toStringAsFixed(6)??'—')),
   ListTile(leading:const Icon(Icons.speed),title:const Text('Speed'),trailing:Text('${((position?.speed??0).clamp(0,999)*3.6).toStringAsFixed(1)} km/h')),
   ListTile(leading:const Icon(Icons.gps_fixed),title:const Text('GPS accuracy'),trailing:Text('${position?.accuracy.toStringAsFixed(1)??'—'} m')),
   ListTile(leading:const Icon(Icons.route),title:const Text('Trip distance'),trailing:Text('${(tracker.meters/1000).toStringAsFixed(2)} km')),
 ])));
}
class HistoryScreen extends StatelessWidget {const HistoryScreen({super.key});
 @override Widget build(BuildContext context){final uid=FirebaseAuth.instance.currentUser!.uid;
  return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('trips').where('ownerId',isEqualTo:uid).snapshots(),builder:(context,s){if(s.hasError)return Center(child:Text('Firestore error: ${s.error}'));if(!s.hasData)return const Center(child:CircularProgressIndicator());
   final docs=[...s.data!.docs]..sort((a,b){final x=(a.data()['startedAt'] as Timestamp?)?.millisecondsSinceEpoch??0;final y=(b.data()['startedAt'] as Timestamp?)?.millisecondsSinceEpoch??0;return y.compareTo(x);});
   if(docs.isEmpty)return const Center(child:Text('No trips yet. Start tracking to save your first route.'));
   return ListView.builder(padding:const EdgeInsets.all(12),itemCount:docs.length,itemBuilder:(context,i){final d=docs[i].data();final start=(d['startedAt'] as Timestamp?)?.toDate();return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.route)),title:Text(start==null?'New trip':DateFormat('dd MMM yyyy • hh:mm a').format(start)),subtitle:Text('${(((d['distanceMeters'] as num?)??0)/1000).toStringAsFixed(2)} km • ${d['active']==true?'Live':'Completed'}'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>TripDetailScreen(tripId:docs[i].id))));});
  });
 }
}
class TripDetailScreen extends StatelessWidget {final String tripId;const TripDetailScreen({super.key,required this.tripId});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Trip Details'),actions:[IconButton(icon:const Icon(Icons.share),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ShareScreen(tripId:tripId))))]),body:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('trips').doc(tripId).snapshots(),builder:(context,t){if(t.hasError)return Center(child:Text('${t.error}'));if(!t.hasData)return const Center(child:CircularProgressIndicator());if(!t.data!.exists)return const Center(child:Text('Trip not available'));final trip=t.data!.data()!;
 return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('trips').doc(tripId).collection('points').orderBy('at').snapshots(),builder:(context,s){if(s.hasError)return Center(child:Text('${s.error}'));if(!s.hasData)return const Center(child:CircularProgressIndicator());final coords=s.data!.docs.map((d)=>LatLng((d.data()['lat'] as num).toDouble(),(d.data()['lng'] as num).toDouble())).toList();final pos=coords.isEmpty?startPlace:coords.last;
  return Column(children:[Expanded(child:GoogleMap(initialCameraPosition:CameraPosition(target:pos,zoom:14),markers:coords.isEmpty?{}:{Marker(markerId:const MarkerId('last'),position:pos)},polylines:{if(coords.length>1)Polyline(polylineId:const PolylineId('trip'),points:coords,color:blue,width:6)})),Padding(padding:const EdgeInsets.all(18),child:Column(children:[Text(trip['active']==true?'LIVE • Last received GPS point':'Saved trip',style:const TextStyle(color:blue,fontWeight:FontWeight.w700)),const SizedBox(height:7),Text('Distance: ${(((trip['distanceMeters'] as num?)??0)/1000).toStringAsFixed(2)} km • GPS points: ${coords.length}'),SelectableText('Trip ID: $tripId',style:const TextStyle(fontSize:11))]))]);
 });}));
}
class ShareScreen extends StatefulWidget {final String? tripId;const ShareScreen({super.key,this.tripId});@override State<ShareScreen> createState()=>_ShareScreenState();}
class _ShareScreenState extends State<ShareScreen> {final viewer=TextEditingController(),id=TextEditingController();bool busy=false;
 @override void initState(){super.initState();id.text=widget.tripId??tracker.tripId??'';}
 @override void dispose(){viewer.dispose();id.dispose();super.dispose();}
 Future<void> share() async {if(id.text.trim().isEmpty||viewer.text.trim().isEmpty){showMsg(context,'Enter trip ID and viewer UID');return;}setState(()=>busy=true);
  try{final ref=FirebaseFirestore.instance.collection('trips').doc(id.text.trim());final doc=await ref.get();if(!doc.exists||doc.data()?['ownerId']!=FirebaseAuth.instance.currentUser!.uid)throw Exception('Only trip owner can share');await ref.update({'viewerIds':FieldValue.arrayUnion([viewer.text.trim()])});if(mounted)showMsg(context,'Viewer approved for this trip');}
  catch(e){if(mounted)showMsg(context,'$e');}finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Share Device / Trip')),body:ListView(padding:const EdgeInsets.all(20),children:[const Icon(Icons.share_location,size:72,color:blue),const SizedBox(height:20),const Text('Approve a trusted viewer',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:7),const Text('For privacy, enter the Firebase UID shown in the viewer’s Profile. Only the selected trip is shared. You can remove access anytime.'),const SizedBox(height:18),TextField(controller:id,decoration:const InputDecoration(labelText:'Your Trip ID')),const SizedBox(height:12),TextField(controller:viewer,decoration:const InputDecoration(labelText:'Viewer UID')),const SizedBox(height:17),ElevatedButton(onPressed:busy?null:share,child:const Text('Grant view-only access')),
  const SizedBox(height:25),const Text('Revoke access',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:8),ElevatedButton(onPressed:busy?null:()async{try{final ref=FirebaseFirestore.instance.collection('trips').doc(id.text.trim());final doc=await ref.get();if(doc.data()?['ownerId']!=FirebaseAuth.instance.currentUser!.uid)throw Exception('Not owner');await ref.update({'viewerIds':FieldValue.arrayRemove([viewer.text.trim()])});if(context.mounted)showMsg(context,'Viewer access removed');}catch(e){if(context.mounted)showMsg(context,'$e');}},child:const Text('Remove viewer')),
  const Divider(height:40),const Text('View a trip shared with you',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:8),ElevatedButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>TripDetailScreen(tripId:id.text.trim()))),child:const Text('Open Trip ID (if authorized)'))]));
}
class GeofenceScreen extends StatefulWidget{const GeofenceScreen({super.key});@override State<GeofenceScreen> createState()=>_GeofenceScreenState();}
class _GeofenceScreenState extends State<GeofenceScreen>{double radius=500; LatLng? center;bool inside=true;bool enabled=false;
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Geofence')),body:AnimatedBuilder(animation:tracker,builder:(context,_) {final p=tracker.current;final loc=p==null?null:LatLng(p.latitude,p.longitude);
  final distance=center==null||loc==null?null:Geolocator.distanceBetween(center!.latitude,center!.longitude,loc.latitude,loc.longitude);
  final nowInside=distance==null||distance<=radius;
  return Column(children:[Expanded(child:GoogleMap(initialCameraPosition:CameraPosition(target:loc??startPlace,zoom:14),onTap:(c)=>setState(()=>center=c),markers:{if(center!=null)Marker(markerId:const MarkerId('center'),position:center!)},circles:{if(center!=null)Circle(circleId:const CircleId('area'),center:center!,radius:radius,fillColor:blue.withValues(alpha:.15),strokeColor:blue,strokeWidth:2)})),Padding(padding:const EdgeInsets.all(18),child:Column(children:[Text('Radius: ${radius.round()} meters'),Slider(min:100,max:2000,divisions:19,value:radius,onChanged:(n)=>setState(()=>radius=n)),const Text('Tap the map to place the safe-zone center. This MVP shows status only while this screen is open.'),const SizedBox(height:7),Text(center==null?'Select an area':loc==null?'Start tracking to compare':'Device is ${nowInside?'INSIDE':'OUTSIDE'} the zone',style:const TextStyle(fontWeight:FontWeight.bold)),ElevatedButton(onPressed:loc==null?null:()=>setState(()=>center=loc),child:const Text('Use my current GPS position'))]))]);
 }));
}
class NotificationsScreen extends StatelessWidget {
 const NotificationsScreen({super.key});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Notifications')),body:ListView(children:const [
  ListTile(leading:CircleAvatar(child:Icon(Icons.notifications_active)),title:Text('Notification center'),subtitle:Text('Push notifications are not activated in this version.')),
  Divider(),ListTile(leading:Icon(Icons.place_outlined,color:blue),title:Text('Geofence alerts'),subtitle:Text('Coming in a future version')),
  ListTile(leading:Icon(Icons.battery_alert_outlined,color:Colors.orange),title:Text('Low battery alerts'),subtitle:Text('Coming in a future version')),
  ListTile(leading:Icon(Icons.speed,color:Colors.red),title:Text('Speed alerts'),subtitle:Text('Coming in a future version')),
 ]));
}
class PremiumScreen extends StatelessWidget {
 const PremiumScreen({super.key});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Premium')),body:ListView(padding:const EdgeInsets.all(24),children:[
 const Icon(Icons.workspace_premium,color:Colors.deepPurple,size:85),const SizedBox(height:20),const Text('Upgrade to Premium',textAlign:TextAlign.center,style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:18),
 const Card(child:Column(children:[ListTile(leading:Icon(Icons.history),title:Text('Extended route history')),ListTile(leading:Icon(Icons.groups),title:Text('More shared viewers')),ListTile(leading:Icon(Icons.radar),title:Text('Advanced geofence alerts'))])),
 const SizedBox(height:20),const Text('Preview only: billing and subscriptions are not configured.',textAlign:TextAlign.center),
 ]));
}

class ProfileScreen extends StatelessWidget{const ProfileScreen({super.key});@override Widget build(BuildContext context){final u=FirebaseAuth.instance.currentUser!;
 return ListView(children:[const SizedBox(height:18),const CircleAvatar(radius:35,child:Icon(Icons.person,size:36)),const SizedBox(height:12),Center(child:Text(u.displayName??'GPS User',style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold))),Center(child:Text(u.email??'')),const SizedBox(height:20),const ListTile(title:Text('My viewer ID (UID)'),subtitle:Text('Share this only with people you want to grant access to.')),Padding(padding:const EdgeInsets.symmetric(horizontal:18),child:SelectableText(u.uid)),const Divider(height:35),ListTile(leading:const Icon(Icons.share),title:const Text('Shared trip / View a trip'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ShareScreen()))),ListTile(leading:const Icon(Icons.workspace_premium_outlined),title:const Text('Premium Plan'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PremiumScreen()))),ListTile(leading:const Icon(Icons.privacy_tip_outlined),title:const Text('Privacy'),subtitle:const Text('Tracking requires permission; stop anytime.')),ListTile(leading:const Icon(Icons.logout,color:Colors.red),title:const Text('Logout',style:TextStyle(color:Colors.red)),onTap:()async{if(tracker.active)await tracker.stop();await FirebaseAuth.instance.signOut();})]);
}}
