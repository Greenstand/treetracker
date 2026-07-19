import React, { useState } from "react";
import {
  GestureResponderEvent,
  Pressable,
  StyleProp,
  StyleSheet,
  Text,
  View,
  ViewStyle,
} from "react-native";
import { AppColors, ButtonColors, DepthColors, Fonts } from "../theme";

// 3D "raised" button matching Android's DepthButton: a shadow-colored base with
// the face offset upward by `depth`, leaving a visible lip at the bottom. Pressing
// pushes the face down onto the base.

type DepthButtonProps = {
  onPress?: (e: GestureResponderEvent) => void;
  colors?: DepthColors;
  enabled?: boolean;
  depth?: number;
  radius?: number;
  circle?: boolean;
  width?: number;
  height?: number;
  style?: StyleProp<ViewStyle>;
  accessibilityLabel?: string;
  children?: React.ReactNode;
};

export function DepthButton({
  onPress,
  colors = ButtonColors.Default,
  enabled = true,
  depth = 7,
  radius = 12,
  circle = false,
  width,
  height,
  style,
  accessibilityLabel,
  children,
}: DepthButtonProps) {
  const [pressed, setPressed] = useState(false);
  const face = enabled ? colors.color : colors.disabledColor;
  const base = enabled ? colors.shadowColor : colors.disabledShadowColor;
  const br = circle ? (height ?? 60) / 2 : radius;

  return (
    <Pressable
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="button"
      accessibilityState={{ disabled: !enabled }}
      disabled={!enabled}
      onPress={onPress}
      onPressIn={() => setPressed(true)}
      onPressOut={() => setPressed(false)}
      style={[{ width, height }, style]}>
      {/* shadow base */}
      <View
        style={[
          StyleSheet.absoluteFill,
          { backgroundColor: base, borderRadius: br },
        ]}
      />
      {/* face */}
      <View
        style={{
          position: "absolute",
          left: 1,
          right: 1,
          top: pressed && enabled ? depth : 0,
          bottom: pressed && enabled ? 0 : depth,
          backgroundColor: face,
          borderRadius: br,
          alignItems: "center",
          justifyContent: "center",
        }}>
        {children}
      </View>
    </Pressable>
  );
}

// Rectangular text button (language buttons, PHONE/EMAIL, NOTE, autofill).
export function DepthTextButton({
  label,
  onPress,
  colors = ButtonColors.ProgressGreen,
  enabled = true,
  width,
  height = 80,
  color = "#191C1F",
  bold = true,
  style,
}: {
  label: string;
  onPress?: () => void;
  colors?: DepthColors;
  enabled?: boolean;
  width?: number;
  height?: number;
  color?: string;
  bold?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  return (
    <DepthButton
      onPress={onPress}
      colors={colors}
      enabled={enabled}
      width={width}
      height={height}
      style={style}>
      <Text
        style={{
          color,
          fontSize: 14,
          fontFamily: bold ? Fonts.bold : Fonts.regular,
          fontWeight: bold ? "bold" : "normal",
        }}>
        {label}
      </Text>
    </DepthButton>
  );
}

// Circular green/red arrow nav button.
export function ArrowButton({
  isLeft,
  onPress,
  enabled = true,
  colors = ButtonColors.ProgressGreen,
}: {
  isLeft: boolean;
  onPress?: () => void;
  enabled?: boolean;
  colors?: DepthColors;
}) {
  return (
    <DepthButton
      circle
      onPress={onPress}
      enabled={enabled}
      colors={colors}
      width={62}
      height={62}
      depth={8}
      accessibilityLabel={isLeft ? "Navigate back" : "Navigate forward"}>
      <Arrow isLeft={isLeft} />
    </DepthButton>
  );
}

// Chunky chevron arrow drawn with two rotated bars (white-on-green like the
// Android arrow_*_green drawable).
function Arrow({ isLeft }: { isLeft: boolean }) {
  // CSS chevron: right+bottom borders, rotate -45° -> points right, 135° -> left.
  return (
    <View
      style={{
        width: 20,
        height: 20,
        transform: [{ rotate: isLeft ? "135deg" : "-45deg" }],
        borderRightWidth: 6,
        borderBottomWidth: 6,
        borderColor: AppColors.Gray,
        marginLeft: isLeft ? 5 : -5,
      }}
    />
  );
}

// Green thumbs-up / red thumbs-down approval button.
export function ApprovalButton({
  approval,
  onPress,
  size = 60,
  accessibilityLabel,
}: {
  approval: boolean;
  onPress?: () => void;
  size?: number;
  accessibilityLabel?: string;
}) {
  return (
    <DepthButton
      circle
      onPress={onPress}
      colors={approval ? ButtonColors.ProgressGreen : ButtonColors.DeclineRed}
      width={size}
      height={size}
      depth={8}
      accessibilityLabel={accessibilityLabel}>
      <Text style={{ fontSize: size * 0.45 }}>{approval ? "👍" : "👎"}</Text>
    </DepthButton>
  );
}

// Camera shutter button: concentric circles inside a green depth circle.
export function CaptureButton({
  onPress,
  enabled = true,
  accessibilityLabel,
}: {
  onPress?: () => void;
  enabled?: boolean;
  accessibilityLabel?: string;
}) {
  return (
    <DepthButton
      circle
      onPress={onPress}
      enabled={enabled}
      colors={ButtonColors.ProgressGreen}
      width={70}
      height={70}
      depth={6}
      accessibilityLabel={accessibilityLabel}>
      <View style={styles.captureOuter}>
        <View style={styles.captureInner} />
      </View>
    </DepthButton>
  );
}

// Orange circular "+" add button.
export function OrangeAddButton({ onPress }: { onPress?: () => void }) {
  return (
    <DepthButton
      circle
      onPress={onPress}
      colors={ButtonColors.UploadOrange}
      width={70}
      height={70}
      depth={8}>
      <Text style={{ color: AppColors.Gray, fontSize: 40, marginTop: -4 }}>+</Text>
    </DepthButton>
  );
}

// Whitish circular info button.
export function InfoButton({ onPress }: { onPress?: () => void }) {
  return (
    <DepthButton
      circle
      onPress={onPress}
      colors={{
        color: "#FFFFFF",
        shadowColor: AppColors.GrayShadow,
        disabledColor: AppColors.GrayShadow,
        disabledShadowColor: AppColors.GrayShadow,
      }}
      width={50}
      height={50}
      depth={5}>
      <Text style={{ color: AppColors.Gray, fontSize: 26, fontWeight: "bold", fontStyle: "italic" }}>
        i
      </Text>
    </DepthButton>
  );
}

const styles = StyleSheet.create({
  captureOuter: {
    width: 54,
    height: 54,
    borderRadius: 27,
    borderWidth: 4,
    borderColor: AppColors.Gray,
    alignItems: "center",
    justifyContent: "center",
  },
  captureInner: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: AppColors.Gray,
  },
});
