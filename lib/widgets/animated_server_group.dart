import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A single frame around a header and lazily built, collapsible server rows.
/// Rows share one animation, so scrolling never replays their entrance and a
/// reversal keeps the existing children until the group has fully closed.
class AnimatedServerGroup extends StatefulWidget {
  const AnimatedServerGroup({
    super.key,
    required this.expanded,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    required this.backgroundColor,
    required this.collapsedBorderColor,
    required this.expandedBorderColor,
  });

  static const duration = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;

  final bool expanded;
  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Color backgroundColor;
  final Color collapsedBorderColor;
  final Color expandedBorderColor;

  @override
  State<AnimatedServerGroup> createState() => _AnimatedServerGroupState();
}

class _AnimatedServerGroupState extends State<AnimatedServerGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AnimatedServerGroup.duration,
    value: widget.expanded ? 1 : 0,
  );
  late final Animation<double> _animation = _controller.drive(
    CurveTween(curve: AnimatedServerGroup.curve),
  );

  @override
  void didUpdateWidget(covariant AnimatedServerGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      if (widget.expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => SliverPadding(
        padding: const EdgeInsets.only(bottom: 12),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color.lerp(
                widget.collapsedBorderColor,
                widget.expandedBorderColor,
                _animation.value,
              )!,
              width: 2,
            ),
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: widget.header),
              // Keep row heights intact and reveal the sliver as a whole.
              // Scaling individual rows toward zero defeats lazy layout.
              if (_animation.value > 0)
                _SliverReveal(
                  factor: _animation.value,
                  child: SliverList.builder(
                    itemCount: widget.itemCount,
                    itemBuilder: widget.itemBuilder,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reveals a normal-height lazy list without asking it to fill the viewport
/// with thousands of almost-zero-height children during animation.
class _SliverReveal extends SingleChildRenderObjectWidget {
  const _SliverReveal({required this.factor, required super.child});

  final double factor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverReveal(factor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverReveal renderObject,
  ) {
    renderObject.factor = factor;
  }
}

class _RenderSliverReveal extends RenderProxySliver {
  _RenderSliverReveal(this._factor);

  double _factor;
  set factor(double value) {
    if (_factor == value) return;
    _factor = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    final original = child!.geometry!;
    if (original.scrollOffsetCorrection != null || _factor == 1) {
      geometry = original;
      return;
    }
    final extent = original.scrollExtent * _factor;
    final remaining = math.max(0.0, extent - constraints.scrollOffset);
    final paintExtent = math.min(original.paintExtent, remaining);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintOrigin: original.paintOrigin,
      paintExtent: paintExtent,
      layoutExtent: math.min(original.layoutExtent, paintExtent),
      maxPaintExtent: original.maxPaintExtent * _factor,
      hitTestExtent: math.min(original.hitTestExtent, paintExtent),
      cacheExtent: math.min(
        original.cacheExtent,
        math.max(0.0, remaining - constraints.cacheOrigin),
      ),
      hasVisualOverflow: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!geometry!.visible) return;
    if (_factor == 1) {
      super.paint(context, offset);
      return;
    }
    final clip = constraints.axis == Axis.vertical
        ? Rect.fromLTWH(
            0,
            0,
            constraints.crossAxisExtent,
            geometry!.paintExtent,
          )
        : Rect.fromLTWH(
            0,
            0,
            geometry!.paintExtent,
            constraints.crossAxisExtent,
          );
    context.pushClipRect(needsCompositing, offset, clip, super.paint);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      constraints.axis == Axis.vertical
      ? Rect.fromLTWH(0, 0, constraints.crossAxisExtent, geometry!.paintExtent)
      : Rect.fromLTWH(0, 0, geometry!.paintExtent, constraints.crossAxisExtent);
}
