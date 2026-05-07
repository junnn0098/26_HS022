import 'package:flutter/material.dart';
import 'dart:async'; // 실시간 타이머를 위해 필요

void main() => runApp(const MaterialApp(home: HaniumApp()));

class HaniumApp extends StatefulWidget {
  const HaniumApp({super.key});

  @override
  State<HaniumApp> createState() => _HaniumAppState();
}

class _HaniumAppState extends State<HaniumApp> {
  // 어르신의 좌표 (x, y) - 일단 앱 내부에서 임시로 움직이게 할 거예요
  double userX = 150.0;
  double userY = 150.0;
  String status = "정상 (재실 중)";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200], // 배경색을 연한 회색으로
      appBar: AppBar(
        title: const Text("Hanium Safety Radar"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          // 1. 상단 상태 카드
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("현재 상태", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(status, style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // 2. 중앙 레이더 화면 (여기가 핵심!)
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                height: 400,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.blueAccent, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    // 배경에 격자무늬나 도면 이미지를 넣을 수 있는 곳
                    Center(child: Text("집 평면도 영역", style: TextStyle(color: Colors.grey[300]))),
                    
                    // 🔴 움직이는 어르신 점 (좌표 기반)
                    Positioned(
                      left: userX,
                      top: userY,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 10)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. 하단 로그/버튼 영역
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: () {
                // 버튼 누르면 랜덤하게 점이 이동하게 테스트!
                setState(() {
                  userX = (userX + 20) % 280;
                  userY = (userY + 30) % 380;
                });
              },
              child: const Text("위치 테스트 (수동 이동)"),
            ),
          ),
        ],
      ),
    );
  }
}