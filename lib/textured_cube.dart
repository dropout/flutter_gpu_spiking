// class TexturedQuadPage extends StatefulWidget {
//   const TexturedQuadPage({super.key});
//   @override
//   State<TexturedQuadPage> createState() => _TexturedQuadPageState();
// }
//
// class _TexturedQuadPageState extends State<TexturedQuadPage> {
//
//   late final Ticker ticker;
//   Duration elapsed = Duration.zero;
//   ui.Image? image;
//
//   @override
//   void initState() {
//     ticker = Ticker(
//       (e) => setState(() { elapsed = e; })
//     );
//     ticker.start();
//     rootBundle.load('assets/images/uv_checker_1k.png').then((bd) {
//       ui.decodeImageFromList(bd.buffer.asUint8List(), (img) {
//         setState(() {
//           image = img;
//           print('image loaded: $image');
//         });
//       });
//     });
//     super.initState();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (image == null) {
//       return const SizedBox.expand(
//         child: Center(
//           child: Text('Loading image...'),
//         ),
//       );
//     }
//
//     return SizedBox.expand(
//       child: CustomPaint(
//         painter: TexturedQuadPainter(
//           texture: image!,
//         ),
//       )
//     );
//   }
//
//   @override
//   void dispose() {
//     ticker.stop();
//     ticker.dispose();
//     super.dispose();
//   }
//
// }