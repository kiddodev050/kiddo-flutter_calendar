import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:timezone/timezone.dart';
import 'dart:async';
import 'sharedcalendarstate.dart';
import 'calendarevent.dart';

const Duration _kExpand = const Duration(milliseconds: 200);

///
/// Displays the header for the calendar.  This handles the title with the
/// month/year and a drop down item as well as opening to show the whole month.
///
class CalendarHeader extends StatefulWidget {
  final Location _location;
  final String calendarKey;

  ///
  /// Creates the calendar header.  [calendarKey] is the key to find the shared
  /// state from.  [location] to use for the calendar.
  ///
  CalendarHeader(this.calendarKey, Location location)
      : _location = location ?? local;

  @override
  State createState() {
    return new CalendarHeaderState();
  }
}

///
/// The calendar state associated with the header.
///
class CalendarHeaderState extends State<CalendarHeader>
    with SingleTickerProviderStateMixin {
  double get maxExtent => 55.0;

  StreamSubscription<int> _subscription;
  StreamSubscription<bool> _headerExpandedSubscription;
  SharedCalendarState sharedState;
  AnimationController _controller;
  CurvedAnimation _easeInAnimation;
  Animation<double> _iconTurns;
  bool myExpandedState = false;
  int _monthIndex;

  int monthIndexFromTime(TZDateTime time) {
    return (time.year - 1970) * 12 + (time.month - 1);
  }

  TZDateTime monthToShow(int index) {
    return new TZDateTime(
        sharedState.location, index ~/ 12 + 1970, index % 12 + 1, 1);
  }

  void initState() {
    super.initState();
    _monthIndex = monthIndexFromTime(new TZDateTime.now(widget._location));
    _controller = new AnimationController(duration: _kExpand, vsync: this);
    sharedState = SharedCalendarState.get(widget.calendarKey);
    _easeInAnimation =
        new CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _iconTurns =
        new Tween<double>(begin: 0.0, end: 0.5).animate(_easeInAnimation);
    sharedState.indexChangeStream.listen((int newTop) {
      setState(() {});
    });
    _headerExpandedSubscription =
        sharedState.headerExpandedChangeStream.listen((bool change) {
      if (myExpandedState != change) {
        setState(() {
          myExpandedState = change;
          _doAnimation();
        });
      }
    });
  }

  void _doAnimation() {
    if (myExpandedState) {
      _controller.forward();
    } else {
      _controller.reverse().then<void>((Null value) {
        setState(() {
          // Rebuild without widget.children.
        });
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    _subscription?.cancel();
    _subscription = null;
    _controller?.dispose();
    _controller = null;
    _headerExpandedSubscription?.cancel();
    _headerExpandedSubscription = null;
  }

  void _handleOpen() {
    setState(() {
      // Jump the page controller to the right spot.
      myExpandedState = !sharedState.headerExpanded;
      sharedState.headerExpanded = myExpandedState;
      _doAnimation();
      PageStorage.of(context)?.writeState(context, sharedState.headerExpanded);
    });
  }

  Widget _buildChildren(BuildContext context, Widget child) {
    return new Container(
      child: new Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildCurrentHeader(context),
          new ClipRect(
            child: new Align(
              heightFactor: _easeInAnimation.value,
              child: new Container(
                constraints:
                    new BoxConstraints(minHeight: 230.0, maxHeight: 230.0),
                child: new Dismissible(
                  key: new ValueKey(_monthIndex),
                  resizeDuration: null,
                  onDismissed: (DismissDirection direction) {
                    setState(() {
                      _monthIndex +=
                          direction == DismissDirection.endToStart ? 1 : -1;
                      // Update the current scroll pos too.
                      sharedState.source.scrollToDay(monthToShow(_monthIndex));
                    });
                  },
                  child: new _CalendarMonthDisplay(
                    sharedState,
                    widget._location,
                    monthToShow(_monthIndex),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return new Material(
      elevation: 4.0,
      color: Colors.white,
      child: new AnimatedBuilder(
        animation: _controller,
        builder: _buildChildren,
        child: _buildCurrentHeader(context),
      ),
    );
  }

  Widget _buildCurrentHeader(BuildContext context) {
    int ms = (sharedState.currentTopIndex + 1) * Duration.millisecondsPerDay;
    TZDateTime currentTopTemp = new TZDateTime.fromMillisecondsSinceEpoch(
        widget._location, ms + widget._location.timeZone(ms).offset);
    TZDateTime currentTop = new TZDateTime(widget._location,
        currentTopTemp.year, currentTopTemp.month, currentTopTemp.day);

    return new Container(
      padding: new EdgeInsets.only(top: 8.0, left: 5.0, bottom: 8.0),
      decoration: new BoxDecoration(
        color: Colors.white,
        image: new DecorationImage(
          image: new AssetImage("assets/images/calendarheader.png"),
          fit: BoxFit.fitHeight,
          alignment: new Alignment(1.0, 1.0),
        ),
      ),
      child: new GestureDetector(
        onTap: _handleOpen,
        child: new Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            new Text(
              myExpandedState
                  ? MaterialLocalizations
                      .of(context)
                      .formatMonthYear(monthToShow(_monthIndex))
                  : MaterialLocalizations
                      .of(context)
                      .formatMonthYear(currentTop),
              style: Theme.of(context).textTheme.title.copyWith(fontSize: 25.0),
            ),
            new RotationTransition(
              turns: _iconTurns,
              child: const Icon(
                Icons.expand_more,
                size: 25.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///
/// Shows a small dot for the event to show the calendar day has a specific
/// event at it.
///
class _CalendarEventIndicator extends CustomPainter {
  final double _radius;
  final CalendarEvent _event;

  _CalendarEventIndicator(this._radius, this._event);

  @override
  void paint(Canvas canvas, Size size) {
    if (_radius == null) return;
    canvas.drawCircle(new Offset(_radius, _radius), _radius,
        new Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_CalendarEventIndicator other) =>
      other._radius != _radius || other._event != _event;
}

///
/// The animated container to show for the month with all the days and the
/// day headers.
///
class _CalendarMonthDisplay extends StatelessWidget {
  final SharedCalendarState sharedState;
  final Location location;
  final TZDateTime displayDate;

  static const Duration week = const Duration(days: 7);

  _CalendarMonthDisplay(this.sharedState, this.location, this.displayDate);

  Widget _eventIndicator(Widget button, int eventIndex) {
    if (sharedState.events.containsKey(eventIndex)) {
      List<Widget> eventIndicators = [];
      for (CalendarEvent event in sharedState.events[eventIndex]) {
        eventIndicators.add(
          new SizedBox(
            height: 4.0,
            width: 4.0,
            child: new CustomPaint(
              painter: new _CalendarEventIndicator(2.0, event),
            ),
          ),
        );
        eventIndicators.add(
          new SizedBox(
            width: 2.0,
          ),
        );
      }
      return new SizedBox(
        width: 40.0,
        height: 40.0,
        child: new Stack(
          children: <Widget>[
            button,
            new Container(
              alignment: new Alignment(1.0, 1.0),
              child: new Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.max,
                children: eventIndicators,
              ),
            ),
          ],
        ),
      );
    } else {
      return new SizedBox(
        width: 40.0,
        height: 40.0,
        child: button,
      );
    }
  }

  Widget _buildButton(ThemeData theme, TZDateTime day, TZDateTime nowTime) {
    Widget button;
    // Only show days in the current month.
    if (day.month != displayDate.month) {
      button = new SizedBox(width: 1.0);
    } else {
      button = new Center(
        child: new FlatButton(
          color: day.isAtSameMomentAs(nowTime)
              ? theme.accentColor
              : day.isAtSameMomentAs(displayDate)
                  ? Colors.grey.shade200
                  : Colors.white,
          shape: new CircleBorder(),
          child: new Text(day.day.toString()),
          onPressed: () => sharedState.source.scrollToDay(day),
          padding: EdgeInsets.zero,
        ),
      );
    }
    int eventIndex = CalendarEvent.indexFromMilliseconds(day, location);
    return _eventIndicator(button, eventIndex);
  }

  @override
  Widget build(BuildContext context) {
     TZDateTime nowTmp = new TZDateTime.now(location);
    TZDateTime nowTime =
        new TZDateTime(location, nowTmp.year, nowTmp.month, nowTmp.day);
    TZDateTime topFirst = displayDate;
    topFirst = topFirst.subtract(new Duration(days: topFirst.weekday));
    TZDateTime topSecond = topFirst.add(week);
    if (topSecond.day == 1) {
      // Opps, out by a week.
      topFirst = topSecond;
      topSecond = topFirst.add(week);
    }
    TZDateTime topThird = topSecond.add(week);
    TZDateTime topFourth = topThird.add(week);
    TZDateTime topFifth = topFourth.add(week);
    List<Widget> dayHeaders = [];
    List<Widget> firstDays = [];
    List<Widget> secondDays = [];
    List<Widget> thirdDays = [];
    List<Widget> fourthDays = [];
    List<Widget> fifthDays = [];
    ThemeData theme = Theme.of(context);

    for (int i = 0; i < 7; i++) {
      dayHeaders.add(
        new SizedBox(
          width: 40.0,
          height: 20.0,
          child: new Center(
            child: new Text(
              MaterialLocalizations
                  .of(context)
                  .narrowWeekdays[topFirst.weekday % 7],
            ),
          ),
        ),
      );

      // First row.
      firstDays.add(_buildButton(theme, topFirst, nowTime));

      // Second row.
      secondDays.add(_buildButton(theme, topSecond, nowTime));

      // Third row.
      thirdDays.add(_buildButton(theme, topThird, nowTime));

      // Fourth row.
      fourthDays.add(_buildButton(theme, topFourth, nowTime));

      // Fifth row.
      fifthDays.add(_buildButton(theme, topFifth, nowTime));

      topFirst = topFirst.add(oneDay);
      topSecond = topSecond.add(oneDay);
      topThird = topThird.add(oneDay);
      topFourth = topFourth.add(oneDay);
      topFifth = topFifth.add(oneDay);
    }

    return new Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: dayHeaders,
        ),
        new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: firstDays,
        ),
        new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: secondDays,
        ),
        new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: thirdDays,
        ),
        new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: fourthDays,
        ),
        new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: fifthDays,
        ),
        new SizedBox(height: 10.0),
      ],
    );
  }
}
