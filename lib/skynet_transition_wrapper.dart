import 'package:flutter/material.dart';

class SkyNetTransitionWrapper extends StatefulWidget {
  final Widget child;

  const SkyNetTransitionWrapper({Key? key, required this.child}) : super(key: key);

  @override
  State<SkyNetTransitionWrapper> createState() => _SkyNetTransitionWrapperState();
}

class _SkyNetTransitionWrapperState extends State<SkyNetTransitionWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animationOne;
  late Animation<double> _animationTwo;
  bool _isAnimationComplete = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    const customCurve = Cubic(0.85, 0.0, 0.15, 1.0);

    _animationOne = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1400 / 1500, curve: customCurve),
      ),
    );

    _animationTwo = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(100 / 1500, 1.0, curve: customCurve),
      ),
    );

    _controller.forward().then((_) {
      setState(() {
        _isAnimationComplete = true;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isAnimationComplete)
          AnimatedBuilder(
            animation: _animationTwo,
            builder: (context, child) {
              return ClipPath(
                clipper: GeoPolygonClipper(_animationTwo.value),
                child: Container(
                  color: const Color(0xFF4F46E5),
                ),
              );
            },
          ),
        if (!_isAnimationComplete)
          AnimatedBuilder(
            animation: _animationOne,
            builder: (context, child) {
              return ClipPath(
                clipper: GeoPolygonClipper(_animationOne.value),
                child: Container(
                  color: const Color(0xFF1E1B4B),
                  child: Center(
                    child: Opacity(
                      opacity: 0.6,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        maxWidth: 650,
                        child: Image.asset(
                          'assets/images/icon.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                  style: BorderStyle.dashed,
                                  width: 2,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class GeoPolygonClipper extends CustomClipper<Path> {
  final double progress;

  GeoPolygonClipper(this.progress);

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    if (progress <= 0.5) {
      final k = progress * 2.0;
      path.moveTo(0, 0);
      path.lineTo(w, 0);
      path.lineTo(w * k, h * k);
      path.lineTo(0, h);
    } else {
      final k = (progress - 0.5) * 2.0;
      path.moveTo(w * k, h * k);
      path.lineTo(w, 0);
      path.lineTo(w, h);
      path.lineTo(w * k, h);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant GeoPolygonClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}