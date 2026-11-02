import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

const baseUrl = String.fromEnvironment('SCL_API_URL', defaultValue: 'https://api.smartcarlock.ir');
const secureStorage = FlutterSecureStorage();
void main() => runApp(const SmartCarApp());

class Api {
  String token = '';
  Future<dynamic> request(String path, {String method = 'GET', Map<String, dynamic>? data}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    if (data != null) headers['Content-Type'] = 'application/json';
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (data != null) request.body = jsonEncode(data);
    final stream = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(stream);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String error = 'خطای سرور: ${response.statusCode}';
      try { error = jsonDecode(utf8.decode(response.bodyBytes))['detail'].toString(); } catch (_) {}
      throw Exception(error);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}

class SmartCarApp extends StatelessWidget {
  const SmartCarApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'SmartCarLock', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1461a4)), useMaterial3: true),
    home: const Directionality(textDirection: TextDirection.rtl, child: AppHome()),
  );
}

class AppHome extends StatefulWidget {const AppHome({super.key}); @override State<AppHome> createState() => _AppHomeState();}
class _AppHomeState extends State<AppHome> {
  final api = Api(); bool loading = true; String? error; List<dynamic> vehicles = []; Map<String, dynamic>? selected;
  Timer? timer; int? selectedId;
  @override void initState(){super.initState(); _restore();}
  @override void dispose(){timer?.cancel(); super.dispose();}
  Future<void> _restore() async {
    api.token = await secureStorage.read(key:'scl_token') ?? '';
    if (api.token.isNotEmpty) { await refresh(); timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh(silent:true)); }
    if (mounted) setState(() => loading=false);
  }
  Future<void> refresh({bool silent=false}) async {
    if(api.token.isEmpty)return;
    try {
      final list = await api.request('/api/vehicles') as List<dynamic>;
      if(!mounted)return;
      setState(() {vehicles=list; selectedId ??= list.isEmpty?null:list.first['id'] as int;
        selected = list.where((v) => v['id']==selectedId).cast<Map<String,dynamic>>().firstOrNull; error=null;});
    } catch(e){if(mounted && !silent)setState(()=>error=e.toString());}
  }
  void loginDone(String token) {
    api.token=token; secureStorage.write(key:'scl_token',value:token);timer?.cancel();
    timer=Timer.periodic(const Duration(seconds:15),(_)=>refresh(silent:true));refresh();setState((){});
  }
  Future<void> logout() async {timer?.cancel(); await secureStorage.delete(key:'scl_token');setState(() {api.token='';vehicles=[];selected=null;selectedId=null;});}
  Future<void> openClaim() async {await showDialog(context:context,builder:(c)=>ClaimDialog(api:api));await refresh();}
  Future<void> sendCommand(String action) async {
    final v=selected;if(v==null)return;
    try {await api.request('/api/vehicles/${v['id']}/commands',method:'POST',data:{'action':action});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فرمان در صف سرور ثبت شد؛ نتیجه قطعی پس از تأیید خودرو مشخص می‌شود')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  @override Widget build(BuildContext context){
    if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(api.token.isEmpty)return LoginPage(api:api,onLogin:loginDone);
    return Scaffold(appBar:AppBar(title:const Text('SmartCarLock'),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh)),IconButton(onPressed:logout,icon:const Icon(Icons.logout))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:openClaim,icon:const Icon(Icons.add),label:const Text('افزودن خودرو')),
      body:RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(14),children:[
        if(error!=null)Card(child:Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:const TextStyle(color:Colors.red)))),
        if(vehicles.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(24),child:Text('خودرویی ثبت نشده است. با کد اتصال، خودرو را به حساب اضافه کنید.'))),
        if(vehicles.isNotEmpty)DropdownButtonFormField<int>(key:ValueKey<int?>(selectedId),initialValue:selectedId,decoration:const InputDecoration(labelText:'خودروی انتخاب‌شده',border:OutlineInputBorder()),
          items:vehicles.map((v)=>DropdownMenuItem<int>(value:v['id'],child:Text('${v['label']} — ${v['plate']}'))).toList(),onChanged:(id){setState((){selectedId=id;selected=vehicles.cast<Map<String,dynamic>>().firstWhere((v)=>v['id']==id);});}),
        if(selected!=null)...[
          const SizedBox(height:12),VehicleHeader(vehicle:selected!),const SizedBox(height:12),
          if(selected!['lat']!=null && selected!['lon']!=null) VehicleMap(vehicle:selected!),
          const SizedBox(height:14),
          if(selected!['role']!='viewer')...[
            Text('کنترل خودرو',style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:5),Wrap(spacing:9,runSpacing:9,children:[
              ActionButton(label:'قفل درب‌ها',icon:Icons.lock,press:()=>sendCommand('doors_lock')),
              ActionButton(label:'بازکردن درب‌ها',icon:Icons.lock_open,press:()=>sendCommand('doors_unlock')),
              ActionButton(label:'صندوق عقب',icon:Icons.directions_car_filled,press:()=>sendCommand('trunk_pulse')),
              ActionButton(label:'آژیر روشن',icon:Icons.notifications_active,press:()=>sendCommand('alarm_on')),
              ActionButton(label:'آژیر خاموش',icon:Icons.notifications_off,press:()=>sendCommand('alarm_off')),
              ActionButton(label:'دریافت وضعیت',icon:Icons.info,press:()=>sendCommand('status')),
              ActionButton(label:'موقعیت',icon:Icons.location_on,press:()=>sendCommand('location')),
            ]),
          ],
          const SizedBox(height:14),
          if(selected!['role']=='owner') IntervalEditor(api:api,vehicle:selected!,onSaved:refresh),
          const SizedBox(height:12),
          OutlinedButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>HistoryPage(api:api,vehicle:selected!))),icon:const Icon(Icons.route),label:const Text('تاریخچه ۹۰ روزه')),
          OutlinedButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CommandsPage(api:api,vehicle:selected!))),icon:const Icon(Icons.list_alt),label:const Text('نتیجه فرمان‌ها')),
          if(selected!['role']=='owner') OutlinedButton.icon(onPressed:()=>showDialog(context:context,builder:(_)=>ShareDialog(api:api,id:selected!['id'] as int)),icon:const Icon(Icons.group_add),label:const Text('اشتراک خودرو با کاربران دیگر')),
          const SizedBox(height:90),
        ]
      ])),
    );
  }
}

class LoginPage extends StatefulWidget {final Api api; final void Function(String) onLogin; const LoginPage({super.key,required this.api,required this.onLogin});@override State<LoginPage> createState()=>_LoginPageState();}
class _LoginPageState extends State<LoginPage>{final name=TextEditingController(),pass=TextEditingController();bool busy=false;String? error;
 @override void dispose(){name.dispose();pass.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Column(children:[
    const Icon(Icons.directions_car,size:70,color:Color(0xff1461a4)),const Text('ورود به SmartCarLock',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    const SizedBox(height:30),TextField(controller:name,decoration:const InputDecoration(labelText:'نام کاربری',border:OutlineInputBorder())),const SizedBox(height:14),
    TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'گذرواژه',border:OutlineInputBorder())),const SizedBox(height:12),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
    FilledButton(onPressed:busy?null:()async{setState(()=>busy=true);try{final x=await widget.api.request('/api/login',method:'POST',data:{'username':name.text.trim(),'password':pass.text});widget.onLogin(x['token'] as String);}catch(e){setState(()=>error=e.toString());}finally{if(mounted)setState(()=>busy=false);}},child:Text(busy?'در حال ورود...':'ورود')),
  ])))));
}
class ClaimDialog extends StatefulWidget{final Api api;const ClaimDialog({super.key,required this.api});@override State<ClaimDialog> createState()=>_ClaimDialogState();}
class _ClaimDialogState extends State<ClaimDialog>{final id=TextEditingController(),code=TextEditingController();String? error;
@override void dispose(){id.dispose();code.dispose();super.dispose();}
@override Widget build(BuildContext context)=>AlertDialog(title:const Text('افزودن خودرو به حساب'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:id,decoration:const InputDecoration(labelText:'شناسه دستگاه')),TextField(controller:code,decoration:const InputDecoration(labelText:'کد اتصال یک‌بارمصرف')),if(error!=null)Text(error!,style:const TextStyle(color:Colors.red))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),FilledButton(onPressed:()async{try{await widget.api.request('/api/vehicles/claim',method:'POST',data:{'device_id':id.text.trim(),'pairing_code':code.text.trim()});if(context.mounted)Navigator.pop(context);}catch(e){setState(()=>error=e.toString());}},child:const Text('افزودن'))]);}
class VehicleHeader extends StatelessWidget{final Map<String,dynamic> vehicle;const VehicleHeader({super.key,required this.vehicle});
@override Widget build(BuildContext context){final t=vehicle['last_seen'] as int?;final online=vehicle['online']==true;return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text(vehicle['label'].toString(),style:Theme.of(context).textTheme.titleLarge),Text('مدل: ${vehicle['make']} | پلاک: ${vehicle['plate']}'),
 Text(online?'ارتباط: آنلاین':'ارتباط: آفلاین',style:TextStyle(color:online?Colors.green:Colors.orange)),
 Text(t==null?'آخرین اتصال: هرگز':'آخرین اتصال: ${DateTime.fromMillisecondsSinceEpoch(t*1000).toLocal()}'),
 Text('سرعت GPS: ${vehicle['speed']??'-'} km/h | دسترسی: ${vehicle['role']}'),
 Text('مصرف ترافیک سرویس: ${(vehicle['tx_bytes']??0)+(vehicle['rx_bytes']??0)} بایت'),
 Text('وضعیت خروجی‌ها: ${jsonEncode(vehicle['outputs'])}'),
 ])));}
}
class ActionButton extends StatelessWidget{final String label;final IconData icon;final VoidCallback press;const ActionButton({super.key,required this.label,required this.icon,required this.press});@override Widget build(BuildContext context)=>OutlinedButton.icon(onPressed:press,icon:Icon(icon),label:Text(label));}
class VehicleMap extends StatelessWidget {final Map<String,dynamic> vehicle;const VehicleMap({super.key,required this.vehicle});
@override Widget build(BuildContext context){final lat=(vehicle['lat'] as num).toDouble(),lon=(vehicle['lon'] as num).toDouble();final point=LatLng(lat,lon);return Column(children:[
 SizedBox(height:260,child:ClipRRect(borderRadius:BorderRadius.circular(14),child:FlutterMap(options:MapOptions(initialCenter:point,initialZoom:15),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'ir.smartcarlock.smartcarlock'),MarkerLayer(markers:[Marker(point:point,width:40,height:40,child:const Icon(Icons.location_pin,size:40,color:Colors.red))]),const RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')])]))),
 Wrap(spacing:8,children:[TextButton(onPressed:()=>_open('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),child:const Text('Google Maps')),
 TextButton(onPressed:()=>_open('geo:$lat,$lon?q=$lat,$lon'),child:const Text('انتخاب نشان / بلد / نقشه نصب‌شده'))]),
 ]);}
Future<void> _open(String url) async {final uri=Uri.parse(url);await launchUrl(uri,mode:LaunchMode.externalApplication);}
}
class IntervalEditor extends StatefulWidget{final Api api;final Map<String,dynamic> vehicle;final Future<void> Function() onSaved;const IntervalEditor({super.key,required this.api,required this.vehicle,required this.onSaved});@override State<IntervalEditor> createState()=>_IntervalEditorState();}
class _IntervalEditorState extends State<IntervalEditor>{late double moving,parked;bool saving=false;
@override void initState(){super.initState();moving=(widget.vehicle['moving_interval'] as num).toDouble();parked=(widget.vehicle['parked_interval'] as num).toDouble();}
@override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text('تنظیم ارسال موقعیت (۱ تا ۳۰۰ ثانیه)',style:Theme.of(context).textTheme.titleMedium),
 Text('در حال حرکت: ${moving.round()} ثانیه'),Slider(value:moving,min:1,max:300,divisions:299,label:'${moving.round()}',onChanged:(v)=>setState(()=>moving=v)),
 Text('در حالت توقف: ${parked.round()} ثانیه'),Slider(value:parked,min:1,max:300,divisions:299,label:'${parked.round()}',onChanged:(v)=>setState(()=>parked=v)),
 FilledButton(onPressed:saving?null:()async{setState(()=>saving=true);try{await widget.api.request('/api/vehicles/${widget.vehicle['id']}/intervals',method:'PUT',data:{'moving':moving.round(),'parked':parked.round()});await widget.onSaved();if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تنظیمات برای ارسال به خودرو ذخیره شد')));}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>saving=false);}},child:const Text('ذخیره بازه‌ها')),
 ])));}
class HistoryPage extends StatefulWidget{final Api api;final Map<String,dynamic> vehicle;const HistoryPage({super.key,required this.api,required this.vehicle});@override State<HistoryPage> createState()=>_HistoryPageState();}
class _HistoryPageState extends State<HistoryPage>{List<dynamic> points=[];int hours=24;bool busy=true;
@override void initState(){super.initState();load();}
Future<void> load()async{setState(()=>busy=true);try{points=await widget.api.request('/api/vehicles/${widget.vehicle['id']}/history?hours=$hours&limit=2000') as List<dynamic>;}catch(_){}if(mounted)setState(()=>busy=false);}
@override Widget build(BuildContext context){final l=points.map((p)=>LatLng((p['lat'] as num).toDouble(),(p['lon'] as num).toDouble())).toList();return Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('تاریخچه مسیر')),body:Column(children:[DropdownButton<int>(value:hours,items:const [DropdownMenuItem(value:24,child:Text('۲۴ ساعت')),DropdownMenuItem(value:168,child:Text('۷ روز')),DropdownMenuItem(value:720,child:Text('۳۰ روز')),DropdownMenuItem(value:2160,child:Text('۹۰ روز'))],onChanged:(v){if(v!=null){hours=v;load();}}),
 Expanded(child:busy?const Center(child:CircularProgressIndicator()):l.isEmpty?const Center(child:Text('موقعیت ثبت‌شده‌ای وجود ندارد')):FlutterMap(options:MapOptions(initialCenter:l.last,initialZoom:12),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'ir.smartcarlock.smartcarlock'),PolylineLayer(polylines:[Polyline(points:l,strokeWidth:4,color:Colors.blue)]),MarkerLayer(markers:[Marker(point:l.last,child:const Icon(Icons.location_pin,color:Colors.red,size:36))]),const RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')])]))])));}
}
class CommandsPage extends StatefulWidget{final Api api;final Map<String,dynamic> vehicle;const CommandsPage({super.key,required this.api,required this.vehicle});@override State<CommandsPage> createState()=>_CommandsPageState();}
class _CommandsPageState extends State<CommandsPage>{List<dynamic> rows=[];@override void initState(){super.initState();refresh();}Future<void> refresh()async{try{rows=await widget.api.request('/api/vehicles/${widget.vehicle['id']}/commands') as List<dynamic>;if(mounted)setState((){});}catch(_){}}
@override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('فرمان‌ها'),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),body:ListView.builder(itemCount:rows.length,itemBuilder:(_,i){final x=rows[i];return ListTile(title:Text('${x['action']} | ${x['state']}'),subtitle:Text('شناسه: ${x['id']} | ${x['result']??'در انتظار تأیید'}'));})));}
class ShareDialog extends StatefulWidget{final Api api;final int id;const ShareDialog({super.key,required this.api,required this.id});@override State<ShareDialog> createState()=>_ShareDialogState();}
class _ShareDialogState extends State<ShareDialog>{final user=TextEditingController();String role='viewer';String? error;@override void dispose(){user.dispose();super.dispose();}
@override Widget build(BuildContext context)=>AlertDialog(title:const Text('افزودن کاربر به خودرو'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:user,decoration:const InputDecoration(labelText:'نام کاربری')),DropdownButton<String>(value:role,items:const [DropdownMenuItem(value:'viewer',child:Text('فقط مشاهده')),DropdownMenuItem(value:'controller',child:Text('کنترل مجاز'))],onChanged:(v)=>setState(()=>role=v??'viewer')),if(error!=null)Text(error!,style:const TextStyle(color:Colors.red))]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),FilledButton(onPressed:()async{try{await widget.api.request('/api/vehicles/${widget.id}/share',method:'POST',data:{'username':user.text.trim(),'role':role});if(context.mounted)Navigator.pop(context);}catch(e){setState(()=>error=e.toString());}},child:const Text('افزودن'))]);}
