import 'package:flutter/material.dart';

class SkyNetLoader {
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return const SkyNetLoaderWidget();
      },
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class SkyNetLoaderWidget extends StatefulWidget {
  const SkyNetLoaderWidget({Key? key}) : super(key: key);

  @override
  State<SkyNetLoaderWidget> createState() => _SkyNetLoaderWidgetState();
}

class _SkyNetLoaderWidgetState extends State<SkyNetLoaderWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x99020204),
      child: Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _controller.value * 2.0 * 3.141592653589793,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFFFF007F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.elliptical(80 + 15 * _controller.value, 90),
                          topRight: Radius.elliptical(90, 80 + 15 * _controller.value),
                          bottomLeft: Radius.elliptical(85, 85),
                          bottomRight: Radius.elliptical(95, 75),
                        ),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: -_controller.value * 2.0 * 3.141592653589793,
                    child: Opacity(
                      opacity: 0.85,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00C6FF), Color(0xFF4F46E5)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.elliptical(95, 75),
                            topRight: Radius.elliptical(85, 85),
                            bottomLeft: Radius.elliptical(90, 80),
                            bottomRight: Radius.elliptical(80, 90),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withOpacity(0.3),
                      blurRadius: 35,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Image.asset(
                    'assets/images/icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const CircleAvatar(
                        backgroundColor: Color(0xFF4F46E5),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}