/**
  Copyright (C) 2012-2016 by Autodesk, Inc.
  All rights reserved.

  Grbl post processor configuration.

  $Revision: 41631 84ec408fb48fdac5f092948d82c4c4495a62c3d2 $
  $Date: 2017-09-28 19:33:03 $

  FORKID {154F7C00-6549-4c77-ADE0-79375FE5F2AA}
*/

description = "Grbl";
vendor = "grbl";
vendorUrl = "https://github.com/grbl/grbl/wiki";
legal = "Copyright (C) 2012-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic milling post for Grbl.";

extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined;


/**
 *  User-defined properties.
 *  @type {Object}
 */
properties = {
	debugMode: false,
	writeMachine: true,
	writeTools: true,
	useG28: true, 				  // Disable to avoid G28 output for safe machine retracts - when disabled you must manually ensure safe retracts
	showSequenceNumbers: false,
	sequenceNumberStart: 10,
	sequenceNumberIncrement: 1,
	separateWordsWithSpace: true  // Specifies that the words should be separated with a white space
};

/**
 *  User-defined property definitions.
 *  @type {Object}
 */
propertyDefinitions = {
	writeMachine: {
		title: "Write machine",
		description: "Output the machine settings in the header of the code.",
		group: 0,
		type: "boolean"
	},
	writeTools: {
		title: "Write tool list",
		description: "Output a tool list in the header of the code.",
		group: 0,
		type: "boolean"
	},
	useG28: {
		title: "G28 Safe retracts",
		description: "Disable to avoid G28 output for safe machine retracts. When disabled, you must manually ensure safe retracts.",
		type: "boolean"
	},
	showSequenceNumbers: {
		title: "Use sequence numbers",
		description: "Use sequence numbers for each block of outputted code.",
		group: 1,
		type: "boolean"
	},
	sequenceNumberStart: {
		title: "Start sequence number",
		description: "The number at which to start the sequence numbers.",
		group: 1,
		type: "integer"
	},
	sequenceNumberIncrement: {
		title: "Sequence number increment",
		description: "The amount by which the sequence number is incremented by in each block.",
		group: 1,
		type: "integer"
	},
	separateWordsWithSpace: {
		title: "Separate words with space",
		description: "Adds spaces between words if 'yes' is selected.",
		type: "boolean"
	},
	debugMode: {
		title: "Debuging output",
		description: "Adds identifiers for code run and properties.",
		type: "boolean"
	}
};

var numberOfToolSlots = 9999;


var mapCoolantTable = new Table(
	[9, 8], {
		initial: COOLANT_OFF,
		force: true
	},
	"Invalid coolant mode"
);

var gFormat = createFormat({
	prefix: "G",
	decimals: 0
});
var mFormat = createFormat({
	prefix: "M",
	decimals: 0
});

var xyzFormat = createFormat({
	decimals: (unit == MM ? 3 : 4)
});
var feedFormat = createFormat({
	decimals: (unit == MM ? 1 : 2)
});
var toolFormat = createFormat({
	decimals: 0
});
var rpmFormat = createFormat({
	decimals: 0
});
var secFormat = createFormat({  // Seconds - range 0.001-1000
	decimals: 3,
	forceDecimal: true
});
var taperFormat = createFormat({
	decimals: 1,
	scale: DEG
});

var xOutput = createVariable({
	prefix: "X"
}, xyzFormat);
var yOutput = createVariable({
	prefix: "Y"
}, xyzFormat);
var zOutput = createVariable({
	prefix: "Z"
}, xyzFormat);
var feedOutput = createVariable({
	prefix: "F"
}, feedFormat);
var sOutput = createVariable({
	prefix: "S",
	force: true
}, rpmFormat);

/**
 *  Circular output.
 */
var iOutput = createReferenceVariable({
	prefix: "I"
}, xyzFormat);
var jOutput = createReferenceVariable({
	prefix: "J"
}, xyzFormat);
var kOutput = createReferenceVariable({
	prefix: "K"
}, xyzFormat);

var gMotionModal = createModal({}, gFormat); 	// Modal group 1 (G0-G3, ...)
var gPlaneModal = createModal({	 				// Modal group 2 (G17-19)
	onchange: function() {
		gMotionModal.reset();
	}
}, gFormat);
var gAbsIncModal = createModal({}, gFormat); 	// Modal group 3 (G90-91)
var gFeedModeModal = createModal({}, gFormat);  // Modal group 5 (G93-94)
var gUnitModal = createModal({}, gFormat); 		// Modal group 6 (G20-21)

var WARNING_WORK_OFFSET = 0;

function onPassThrough(text) {
    var commands = String(text).split(",");
    for (text in commands) {
        writeBlock(commands[text]);
    }
}

/**
 *  Collected state.
 */
var sequenceNumber;
var currentWorkOffset;

/**
  Writes the specified block.
*/
function writeBlock() {
	if (properties.showSequenceNumbers) {
		writeWords2("N" + sequenceNumber, arguments);
		sequenceNumber += properties.sequenceNumberIncrement;
	} else {
		writeWords(arguments);
	}
}

function formatComment(text) {
	return "(" + String(text).replace(/[\(\)]/g, "") + ")";
}

/**
  Output a comment.
*/
function writeComment(text) {
	writeln(formatComment(text));
}
function writeObject(text) {
	var newText = text;
	var newLength = newText.length;
	var indexOffset = 0;
	var indentLevel = 0;
	var inString = false;

	for (var i = 0; i < text.length; i++) {
		if (text[i] === '{') {  // Increase indent
			indentLevel += 1;
		} else if (text[i] === '}' && indentLevel) {  // Decrease indent
			indentLevel -= 1;
		}
		if (text[i] === '"') {  // Enter or exit a string
			inString = !inString;
		}

		if (text[i].match(/[\{\,\}]/i) && !inString) {  // New line
			var str = newText.substr(0, i + indexOffset) + (text[i] !== '}' ? text[i] : '') + '\n';
			for (var x = 0; x < indentLevel; x++) {
				str += '\t';
			}
			str += (text[i] === '}' ? text[i] : '') + newText.substr(i + indexOffset + 1);

			newText = str;
		}

		indexOffset = newText.length - text.length;
	}

	newText = newText.replace(/\:/g, ': ');
	writeln(newText);
}

function onOpen() {

	if (properties.debugMode) {
		writeObject('Properties:' + JSON.stringify(properties));
	}

	if (!properties.separateWordsWithSpace) {
		setWordSeparator("");
	}

	sequenceNumber = properties.sequenceNumberStart;
	writeln("%");

	if (programName) {
		writeComment(programName);
	}
	if (programComment) {
		writeComment(programComment);
	}

	// Dump machine configuration
	var vendor = machineConfiguration.getVendor();
	var model = machineConfiguration.getModel();
	var description = machineConfiguration.getDescription();

	if (properties.writeMachine && (vendor || model || description)) {
		writeComment(localize("Machine"));
		if (vendor) {
			writeComment("  " + localize("vendor") + ": " + vendor);
		}
		if (model) {
			writeComment("  " + localize("model") + ": " + model);
		}
		if (description) {
			writeComment("  " + localize("description") + ": " + description);
		}
	}

	if (properties.writeTools) {  // Dump tool information
		var zRanges = {};
		if (is3D()) {
			var numberOfSections = getNumberOfSections();
			for (var i = 0; i < numberOfSections; ++i) {
				var section = getSection(i);
				var zRange = section.getGlobalZRange();
				var tool = section.getTool();
				if (zRanges[tool.number]) {
					zRanges[tool.number].expandToRange(zRange);
				} else {
					zRanges[tool.number] = zRange;
				}
			}
		}

		var tools = getToolTable();
		if (tools.getNumberOfTools() > 0) {
			for (var i = 0; i < tools.getNumberOfTools(); ++i) {
				var tool = tools.getTool(i);
				var comment = "T" + toolFormat.format(tool.number) + "  " +
					"D=" + xyzFormat.format(tool.diameter) + " " +
					localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
				if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
					comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
				}
				if (zRanges[tool.number]) {
					comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
				}
				comment += " - " + getToolTypeName(tool.type);
				writeComment(comment);
			}
		}
	}

	if ((getNumberOfSections() > 0) && (getSection(0).workOffset == 0)) {
		for (var i = 0; i < getNumberOfSections(); ++i) {
			if (getSection(i).workOffset > 0) {
				error(localize("Using multiple work offsets is not possible if the initial work offset is 0."));
				return;
			}
		}
	}

	writeBlock(gAbsIncModal.format(90), gFeedModeModal.format(94));  // Absolute coordinates and feed per minute
	writeBlock(gPlaneModal.format(17));

	switch (unit) {
		case IN:
			writeBlock(gUnitModal.format(20));
			break;
		case MM:
			writeBlock(gUnitModal.format(21));
			break;
	}
}

function onComment(message) {
	writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}
/**
 *  Force output of X, Y, and Z.
 */
function forceAny() {
	forceXYZ();
	feedOutput.reset();
}

function onParameter() {

	if (properties.debugMode) {
		writeln('fn onParameter(' + arguments[0] + ': ' + arguments[1] + ')');
	}

}

function onSection() {

	if (properties.debugMode) {
		writeln('fn onSection()');
	}

	var insertToolCall = isFirstSection() ||
		currentSection.getForceToolChange && currentSection.getForceToolChange() ||
		(tool.number != getPreviousSection().getTool().number);

	var retracted = false;  // Specifies that the tool has been retracted to the safe plane
	var newWorkOffset = isFirstSection() || (getPreviousSection().workOffset != currentSection.workOffset);  // Work offset changes
	var newWorkPlane = isFirstSection() || !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

	if (insertToolCall || newWorkOffset || newWorkPlane) {
		if (insertToolCall && !isFirstSection()) {
			onCommand(COMMAND_STOP_SPINDLE);  // Stop spindle before retract during tool change
		}

		if (properties.useG28) {
			retracted = true;  // Retract to safe plane
			writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
			writeBlock(gAbsIncModal.format(90));
			zOutput.reset();
		}
	}

	writeln("");

	if (hasParameter("operation-comment")) {
		var comment = getParameter("operation-comment");
		if (comment) {
			writeComment(comment);
		}
	}

	if (insertToolCall) {
		retracted = true;
		onCommand(COMMAND_COOLANT_OFF);

		if (tool.number > numberOfToolSlots) {
			warning(localize("Tool number exceeds maximum value."));
		}

		writeBlock("T" + toolFormat.format(tool.number), mFormat.format(6));
		if (tool.comment) {
			writeComment(tool.comment);
		}
		var showToolZMin = false;

		if (showToolZMin) {
			if (is3D()) {
				var numberOfSections = getNumberOfSections();
				var zRange = currentSection.getGlobalZRange();
				var number = tool.number;
				for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
					var section = getSection(i);
					if (section.getTool().number != number) {
						break;
					}
					zRange.expandToRange(section.getGlobalZRange());
				}
				writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
			}
		}
	}

	if (insertToolCall || isFirstSection() || (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) || (tool.clockwise != getPreviousSection().getTool().clockwise)) {
		if (tool.spindleRPM < 1) {
			error(localize("Spindle speed out of range."));
		}
		if (tool.spindleRPM > 99999) {
			warning(localize("Spindle speed exceeds maximum value."));
		}
		writeBlock(
			sOutput.format(tool.spindleRPM), mFormat.format(tool.clockwise ? 3 : 4)
		);
	}

	if (insertToolCall) {
		currentWorkOffset = undefined;  // Force work offset when changing tool
	}
	var workOffset = currentSection.workOffset;
	if (workOffset == 0) {
		warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
		workOffset = 1;
	}
	if (workOffset > 0) {
		if (workOffset > 6) {
			error(localize("Work offset out of range."));
			return;
		} else {
			if (workOffset != currentWorkOffset) {
				writeBlock(gFormat.format(53 + workOffset));  // G54 -> G59
				currentWorkOffset = workOffset;
			}
		}
	}

	forceXYZ();

	// Pure 3D
	{
		var remaining = currentSection.workPlane;
		if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
			error(localize("Tool orientation is not supported."));
			return;
		}
		setRotation(remaining);
	}

	// Set coolant after we have positioned at Z
	{
		var c = mapCoolantTable.lookup(tool.coolant);
		if (c) {
			writeBlock(mFormat.format(c));
		} else {
			warning(localize("Coolant not supported."));
		}
	}

	forceAny();

	var initialPosition = getFramePosition(currentSection.getInitialPosition());
	if (!retracted) {
		if (getCurrentPosition().z < initialPosition.z) {
			writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
		}
	}

	if (insertToolCall || retracted) {
		var lengthOffset = tool.lengthOffset;
		if (lengthOffset > numberOfToolSlots) {
			error(localize("Length offset out of range."));
			return;
		}

		gMotionModal.reset();
		writeBlock(gPlaneModal.format(17));

		if (!machineConfiguration.isHeadConfiguration()) {
			writeBlock(
				gAbsIncModal.format(90),
				gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
			);
			writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
		} else {
			writeBlock(
				gAbsIncModal.format(90),
				gMotionModal.format(0),
				xOutput.format(initialPosition.x),
				yOutput.format(initialPosition.y),
				zOutput.format(initialPosition.z)
			);
		}
	} else {
		writeBlock(
			gAbsIncModal.format(90),
			gMotionModal.format(0),
			xOutput.format(initialPosition.x),
			yOutput.format(initialPosition.y)
		);
	}
}

function onDwell(seconds) {
	if (seconds > 99999.999) {
		warning(localize("Dwelling time is out of range."));
	}
	seconds = clamp(0.001, seconds, 99999.999);
	writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
	writeBlock(sOutput.format(spindleSpeed));
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
	pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
	var x = xOutput.format(_x);
	var y = yOutput.format(_y);
	var z = zOutput.format(_z);
	if (x || y || z) {
		if (pendingRadiusCompensation >= 0) {
			error(localize("Radius compensation mode cannot be changed at rapid traversal."));
			return;
		}
		writeBlock(gMotionModal.format(0), x, y, z);
		feedOutput.reset();
	}
}

function onLinear(_x, _y, _z, feed) {
	if (pendingRadiusCompensation >= 0) {  // At least one axis is required
		xOutput.reset();  // Ensure that we end at desired position when compensation is turned off
		yOutput.reset();
	}
	var x = xOutput.format(_x);
	var y = yOutput.format(_y);
	var z = zOutput.format(_z);
	var f = feedOutput.format(feed);
	if (x || y || z) {
		if (pendingRadiusCompensation >= 0) {
			error(localize("Radius compensation mode is not supported."));
			return;
		} else {
			writeBlock(gMotionModal.format(1), x, y, z, f);
		}
	} else if (f) {
		if (getNextRecord().isMotion()) {  // Try not to output feed without motion
			feedOutput.reset();  // Force feed on next line
		} else {
			writeBlock(gMotionModal.format(1), f);
		}
	}
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
	error(localize("Multi-axis motion is not supported."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
	error(localize("Multi-axis motion is not supported."));
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {  // One of X/Y and I/J are required and likewise

	if (pendingRadiusCompensation >= 0) {
		error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
		return;
	}

	var start = getCurrentPosition();

	if (isFullCircle()) {
		if (isHelical()) {
			linearize(tolerance);
			return;
		}
		switch (getCircularPlane()) {
			case PLANE_XY:
				writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
				break;
			case PLANE_ZX:
				writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
				break;
			case PLANE_YZ:
				writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), yOutput.format(y), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
				break;
			default:
				linearize(tolerance);
		}
	} else {
		switch (getCircularPlane()) {
			case PLANE_XY:
				writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
				break;
			case PLANE_ZX:
				writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
				break;
			case PLANE_YZ:
				writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
				break;
			default:
				linearize(tolerance);
		}
	}
}

var mapCommand = {
	COMMAND_STOP: 0,
	COMMAND_END: 2,
	COMMAND_SPINDLE_CLOCKWISE: 3,
	COMMAND_SPINDLE_COUNTERCLOCKWISE: 4,
	COMMAND_STOP_SPINDLE: 5,
	COMMAND_COOLANT_ON: 8,
	COMMAND_COOLANT_OFF: 9
};

function onCommand(command) {
	switch (command) {
		case COMMAND_START_SPINDLE:
			onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
			return;
		case COMMAND_LOCK_MULTI_AXIS:
			return;
		case COMMAND_UNLOCK_MULTI_AXIS:
			return;
		case COMMAND_BREAK_CONTROL:
			return;
		case COMMAND_TOOL_MEASURE:
			return;
	}

	var stringId = getCommandStringId(command);
	var mcode = mapCommand[stringId];
	if (mcode != undefined) {
		writeBlock(mFormat.format(mcode));
	} else {
		onUnsupportedCommand(command);
	}
}

function onSectionEnd() {
	if (properties.debugMode) {
		writeln('fn onSectionEnd()');
	}

	writeBlock(gPlaneModal.format(17));
	forceAny();
}

function onClose() {
	if (properties.debugMode) {
		writeln('fn onClose()');
	}

	onCommand(COMMAND_COOLANT_OFF);

	if (properties.useG28) {
		writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
		zOutput.reset();
	}

	if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
		if (properties.useG28) {
			writeBlock(gFormat.format(28), gAbsIncModal.format(91), "X" + xyzFormat.format(0), "Y" + xyzFormat.format(0)); // return to home
		}
	} else {
		var homeX;
		if (machineConfiguration.hasHomePositionX()) {
			homeX = "X" + xyzFormat.format(machineConfiguration.getHomePositionX());
		}
		var homeY;
		if (machineConfiguration.hasHomePositionY()) {
			homeY = "Y" + xyzFormat.format(machineConfiguration.getHomePositionY());
		}
		writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), homeX, homeY);
	}

	onImpliedCommand(COMMAND_END);
	onImpliedCommand(COMMAND_STOP_SPINDLE);
	writeBlock(mFormat.format(30));  // Stop program, spindle stop, coolant off
	writeln("%");
}
