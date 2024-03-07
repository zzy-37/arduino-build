#include <Arduino.h>
#include <Servo.h>
#include "avr/Servo.cpp"

Servo s;

void setup() {
    s.attach(9);
}

void loop() {
    s.write(100);
}