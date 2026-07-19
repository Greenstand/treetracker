import React from "react";
import {
  KeyboardTypeOptions,
  StyleProp,
  StyleSheet,
  TextInput,
  ViewStyle,
} from "react-native";
import { AppColors, Fonts, TextColors } from "../theme";

// Matches Android BorderedTextField: 0.5dp white border, 16dp rounded corners,
// dark background, white text & placeholder, no underline.
export function BorderedTextField({
  value,
  onChangeText,
  placeholder,
  keyboardType,
  autoCapitalize = "sentences",
  autoCorrect = true,
  style,
  onSubmitEditing,
}: {
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;
  keyboardType?: KeyboardTypeOptions;
  autoCapitalize?: "none" | "sentences" | "words" | "characters";
  autoCorrect?: boolean;
  style?: StyleProp<ViewStyle>;
  onSubmitEditing?: () => void;
}) {
  return (
    <TextInput
      style={[styles.field, style]}
      value={value}
      onChangeText={onChangeText}
      placeholder={placeholder}
      placeholderTextColor={TextColors.white}
      keyboardType={keyboardType}
      autoCapitalize={autoCapitalize}
      autoCorrect={autoCorrect}
      onSubmitEditing={onSubmitEditing}
      cursorColor={AppColors.Green}
    />
  );
}

const styles = StyleSheet.create({
  field: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: TextColors.white,
    borderRadius: 16,
    backgroundColor: AppColors.Gray,
    color: TextColors.white,
    fontFamily: Fonts.regular,
    fontSize: 14,
    paddingHorizontal: 12,
    paddingVertical: 12,
  },
});
