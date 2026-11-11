import 'dart:async';

import 'package:flutter/material.dart';

import 'core/control_word.dart';
import 'core/opcode.dart';
import 'cpu_layout.dart';

class CPUBoard extends StatefulWidget {
  const CPUBoard({super.key});

  @override
  State<CPUBoard> createState() => _CPUBoardState();
}

class _CPUBoardState extends State<CPUBoard> with TickerProviderStateMixin {
  // Bus and control signals
  int bus = 0;
  bool busActive = false;

  // Registers
  int registerA = 0;
  int registerB = 0;
  int instructionRegister = 0;
  int memoryAddressRegister = 0;
  int programCounter = 0;
  int outputRegister = 0;
  int sumRegister = 0;

  // Flags
  bool carryFlag = false;
  bool zeroFlag = false;

  // Control signals
  bool clockHigh = false;
  bool haltFlag = false;
  bool memoryIn = false;
  bool ramIn = false;
  bool ramOut = false;
  bool instructionOut = false;
  bool instructionIn = false;
  bool aRegisterIn = false;
  bool aRegisterOut = false;
  bool bRegisterIn = false;
  bool sumOut = false;
  bool subtract = false;
  bool outputIn = false;
  bool counterEnable = false;
  bool counterOut = false;
  bool jump = false;
  bool flagsIn = false;

  // RAM (16 bytes - 4-bit addressing)
  List<int> ram = List.filled(16, 0);

  // Clock
  Timer? clockTimer;
  Timer? singleStepTimer; // pending falling edge of a manual step
  bool isRunning = false;
  double clockSpeed = 10.0;
  bool manualMode = false;

  // Animation
  late AnimationController busAnimationController;
  late Animation<double> busAnimation;

  // Microcode step
  int microStep = 0;

  // Control word
  int controlWord = 0;

  @override
  void initState() {
    super.initState();

    busAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    busAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(busAnimationController);

    _onLoadProgram();
  }

  void _onLoadProgram([List<int>? program]) {
    _clearRam();

    if (program != null && program.isNotEmpty) {
      for (int i = 0; i < program.length && i < ram.length; i++) {
        ram[i] = program[i];
      }
      return;
    }
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    singleStepTimer?.cancel();
    busAnimationController.dispose();
    super.dispose();
  }

  void _onClockToggle() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning && !haltFlag) {
        _runClock();
      } else {
        clockTimer?.cancel();
      }
    });
  }

  void _runClock() {
    clockTimer = Timer.periodic(
      Duration(milliseconds: (500 / clockSpeed).round()),
      (_) => _clockPulse(),
    );
  }

  void _clockPulse() {
    if (haltFlag) {
      clockTimer?.cancel();
      isRunning = false;
      return;
    }

    setState(() {
      clockHigh = !clockHigh;
      if (!clockHigh) {
        _executeStep();
      }
    });
  }

  void _onClockSingleStep() {
    // Ignore presses while the previous step is still pending, otherwise a
    // double press runs two steps back to back.
    if (haltFlag || singleStepTimer != null) return;

    setState(() {
      clockHigh = true;
    });
    singleStepTimer = Timer(const Duration(milliseconds: 100), () {
      singleStepTimer = null;
      if (!mounted) return;
      setState(() {
        clockHigh = false;
        _executeStep();
      });
    });
  }

  void _executeStep() {
    _onClearControlSignals();

    // T0 and T1 are always the same (fetch cycle)
    if (microStep == 0) {
      // T0: MAR <- PC
      controlWord = ControlWord.co.hex | ControlWord.mi.hex; // CO|MI
      _decodeControlWord(controlWord);
      bus = programCounter;
      busActive = true;
      memoryAddressRegister = bus;
    } else if (microStep == 1) {
      // T1: IR <- RAM[MAR], PC++
      controlWord =
          ControlWord.ro.hex |
          ControlWord.ii.hex |
          ControlWord.ce.hex; // RO|II|CE
      _decodeControlWord(controlWord);
      bus = ram[memoryAddressRegister];
      busActive = true;
      instructionRegister = bus;
      programCounter = (programCounter + 1) & 0xF; // 4-bit counter (0-15)
    } else {
      // Execute cycle (T2+) based on instruction
      _executeInstruction();
    }

    microStep++;

    if (busActive) {
      busAnimationController.forward(from: 0);
    }
  }

  void _executeInstruction() {
    final opcode = Opcode.fromHex((instructionRegister >> 4) & 0xF);
    final operand = instructionRegister & 0xF;

    switch (opcode) {
      case Opcode.nop:
        microStep = -1;
        break;

      case Opcode.lda:
        if (microStep == 2) {
          // ? IO|MI
          controlWord = ControlWord.io.hex | ControlWord.mi.hex;
          _decodeControlWord(controlWord);
          bus = operand;
          busActive = true;
          memoryAddressRegister = bus;
        } else if (microStep == 3) {
          // ? RO|AI
          controlWord = ControlWord.ro.hex | ControlWord.ai.hex;
          _decodeControlWord(controlWord);
          bus = ram[memoryAddressRegister];
          busActive = true;
          registerA = bus;
          microStep = -1;
        }
        break;

      case Opcode.add:
        if (microStep == 2) {
          // ? IO|MI
          controlWord = ControlWord.io.hex | ControlWord.mi.hex;
          _decodeControlWord(controlWord);
          bus = operand;
          busActive = true;
          memoryAddressRegister = bus;
        } else if (microStep == 3) {
          // ? RO|BI
          controlWord = ControlWord.ro.hex | ControlWord.bi.hex;
          _decodeControlWord(controlWord);
          bus = ram[memoryAddressRegister];
          busActive = true;
          registerB = bus;
        } else if (microStep == 4) {
          // ? SO|AI|FI (SO is Sum Out, also called EO)
          controlWord =
              ControlWord.so.hex | ControlWord.ai.hex | ControlWord.fi.hex;
          _decodeControlWord(controlWord);
          final int result = registerA + registerB;
          sumRegister = result & 0xFF;
          bus = sumRegister;
          busActive = true;
          registerA = bus;
          if (flagsIn) {
            carryFlag = result > 0xFF;
            zeroFlag = bus == 0;
          }
          microStep = -1;
        }
        break;

      case Opcode.sub:
        if (microStep == 2) {
          // ? IO|MI
          controlWord = ControlWord.io.hex | ControlWord.mi.hex;
          _decodeControlWord(controlWord);
          bus = operand;
          busActive = true;
          memoryAddressRegister = bus;
        } else if (microStep == 3) {
          // ? RO|BI
          controlWord = ControlWord.ro.hex | ControlWord.bi.hex;
          _decodeControlWord(controlWord);
          bus = ram[memoryAddressRegister];
          busActive = true;
          registerB = bus;
        } else if (microStep == 4) {
          // ? SO|AI|SU|FI
          controlWord =
              ControlWord.so.hex |
              ControlWord.ai.hex |
              ControlWord.su.hex |
              ControlWord.fi.hex;
          _decodeControlWord(controlWord);
          final int oldA = registerA;
          sumRegister = (registerA - registerB) & 0xFF;
          bus = sumRegister;
          busActive = true;
          registerA = bus;
          if (flagsIn) {
            carryFlag = oldA < registerB;
            zeroFlag = bus == 0;
          }
          microStep = -1;
        }
        break;

      case Opcode.sta:
        if (microStep == 2) {
          // ? IO|MI
          controlWord = ControlWord.io.hex | ControlWord.mi.hex;
          _decodeControlWord(controlWord);
          bus = operand;
          busActive = true;
          memoryAddressRegister = bus;
        } else if (microStep == 3) {
          // ? AO|RI
          controlWord = ControlWord.ao.hex | ControlWord.ri.hex;
          _decodeControlWord(controlWord);
          bus = registerA;
          busActive = true;
          ram[memoryAddressRegister] = bus;
          microStep = -1;
        }
        break;

      case Opcode.ldi:
        if (microStep == 2) {
          // ? IO|AI
          controlWord = ControlWord.io.hex | ControlWord.ai.hex;
          _decodeControlWord(controlWord);
          bus = operand;
          busActive = true;
          registerA = bus;
          microStep = -1;
        }
        break;

      case Opcode.jmp:
        if (microStep == 2) {
          // ? IO|J
          controlWord = ControlWord.io.hex | ControlWord.j.hex;
          _decodeControlWord(controlWord);
          bus = operand;
          busActive = true;
          programCounter = bus;
          microStep = -1;
        }
        break;

      case Opcode.jc:
        if (microStep == 2) {
          if (carryFlag) {
            // ? IO|J
            controlWord = ControlWord.io.hex | ControlWord.j.hex;
            _decodeControlWord(controlWord);
            bus = operand;
            busActive = true;
            programCounter = bus;
          }
          microStep = -1;
        }
        break;

      case Opcode.jz:
        if (microStep == 2) {
          if (zeroFlag) {
            // ? IO|J
            controlWord = ControlWord.io.hex | ControlWord.j.hex;
            _decodeControlWord(controlWord);
            bus = operand;
            busActive = true;
            programCounter = bus;
          }
          microStep = -1;
        }
        break;

      case Opcode.out:
        if (microStep == 2) {
          // ? AO|OI
          controlWord = ControlWord.ao.hex | ControlWord.oi.hex;
          _decodeControlWord(controlWord);
          bus = registerA;
          busActive = true;
          outputRegister = bus;
          microStep = -1;
        }
        break;

      case Opcode.hlt:
        haltFlag = true;
        microStep = -1;
        break;
    }
  }

  void _onClearControlSignals() {
    busActive = false;
    memoryIn = false;
    ramIn = false;
    ramOut = false;
    instructionOut = false;
    instructionIn = false;
    aRegisterIn = false;
    aRegisterOut = false;
    bRegisterIn = false;
    sumOut = false;
    subtract = false;
    outputIn = false;
    counterEnable = false;
    counterOut = false;
    jump = false;
    flagsIn = false;
  }

  void _decodeControlWord(int word) {
    memoryIn = ControlWord.mi.isActive(word);
    ramIn = ControlWord.ri.isActive(word);
    ramOut = ControlWord.ro.isActive(word);
    instructionOut = ControlWord.io.isActive(word);
    instructionIn = ControlWord.ii.isActive(word);
    aRegisterIn = ControlWord.ai.isActive(word);
    aRegisterOut = ControlWord.ao.isActive(word);
    bRegisterIn = ControlWord.bi.isActive(word);
    sumOut = ControlWord.so.isActive(word);
    subtract = ControlWord.su.isActive(word);
    outputIn = ControlWord.oi.isActive(word);
    counterEnable = ControlWord.ce.isActive(word);
    counterOut = ControlWord.co.isActive(word);
    jump = ControlWord.j.isActive(word);
    flagsIn = ControlWord.fi.isActive(word);
  }

  void _onReset() {
    setState(() {
      clockTimer?.cancel();
      singleStepTimer?.cancel();
      singleStepTimer = null;
      isRunning = false;
      bus = 0;
      busActive = false;
      registerA = 0;
      registerB = 0;
      instructionRegister = 0;
      memoryAddressRegister = 0;
      programCounter = 0;
      outputRegister = 0;
      sumRegister = 0;
      carryFlag = false;
      zeroFlag = false;
      clockHigh = false;
      haltFlag = false;
      microStep = 0;
      controlWord = 0;

      _onClearControlSignals();
      _clearRam();
      _onLoadProgram();
    });
  }

  void _clearRam() {
    ram = List.filled(16, 0); // * 4-bit addressing (16 bytes)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: CPULayout(
        // ? Bus
        bus: bus,
        busActive: busActive,

        // ? Registers
        registerA: registerA,
        registerB: registerB,
        instructionRegister: instructionRegister,
        memoryAddressRegister: memoryAddressRegister,
        programCounter: programCounter,
        outputRegister: outputRegister,
        sumRegister: sumRegister,

        // ? Flags
        carryFlag: carryFlag,
        zeroFlag: zeroFlag,

        // ? Control signals
        clockHigh: clockHigh,
        haltFlag: haltFlag,
        memoryIn: memoryIn,
        ramIn: ramIn,
        ramOut: ramOut,
        instructionOut: instructionOut,
        instructionIn: instructionIn,
        aRegisterIn: aRegisterIn,
        aRegisterOut: aRegisterOut,
        bRegisterIn: bRegisterIn,
        sumOut: sumOut,
        subtract: subtract,
        outputIn: outputIn,
        counterEnable: counterEnable,
        counterOut: counterOut,
        jump: jump,
        flagsIn: flagsIn,

        // ? RAM
        ram: ram,

        // ? Clock
        isRunning: isRunning,
        clockSpeed: clockSpeed,
        manualMode: manualMode,

        // ? Animation
        busAnimation: busAnimation,

        // ? Microcode step
        microStep: microStep,

        // ? Control word
        controlWord: controlWord,

        // ? Clock
        onClockToggle: _onClockToggle,
        onClockSingleStep: _onClockSingleStep,
        onClockSpeedChanged: (speed) {
          setState(() {
            clockSpeed = speed;
            if (isRunning) {
              clockTimer?.cancel();
              _runClock();
            }
          });
        },
        onClockManualModeChanged: (manual) {
          setState(() {
            manualMode = manual;
          });
        },

        // ? RAM
        onRamEdit: (address, value) {
          setState(() {
            ram[address] = value;
          });
        },

        // ? CPU
        onReset: _onReset,
        onClearControlSignals: _onClearControlSignals,
        onLoadProgram: _onLoadProgram,
      ),
    );
  }
}
