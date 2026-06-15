// Design tokens ported 1:1 from the Android app
// (view/Colors.kt + theme/CustomTheme.kt) so the RN UI matches exactly.

export const AppColors = {
  Gray: "#191C1F",
  GrayShadow: "#000000",
  LightGray: "#D8D8D8",

  Green: "#75B926",
  GreenShadow: "#507924",
  GreenDisabled: "#AD52811A", // ARGB in Kotlin (0xAD...) -> approximated below
  GreenShadowDisabled: "#AA273C12",

  Purple: "#C614A7",
  PurpleShadow: "#7C0868",

  Red: "#EA2525",
  RedShadow: "#A20000",

  Orange: "#F19400",
  OrangeShadow: "#EA6225",

  MediumGray: "#9E9E9E",
  DeepGray: "#333333",
};

// Text colors (CustomTheme.kt)
export const TextColors = {
  lightText: "#F0F0F0",
  darkText: "#191C1F",
  primaryText: AppColors.Green,
  uploadText: "#F19400",
  white: "#FFFFFF",
};

// Typography: Montserrat at the four sizes from CustomTypography.
export const Typography = {
  small: 12,
  regular: 14,
  medium: 16,
  large: 24,
};

// Montserrat ttf files are bundled in assets/fonts and loaded via expo-font in
// the native build. In the Expo Go preview expo-font isn't installed, so these
// stay undefined and the system sans-serif is used (visually close).
export const Fonts: { regular?: string; bold?: string } = {
  regular: undefined,
  bold: undefined,
};

// DepthButton color sets (AppButtonColors). color = face, shadow = base.
export type DepthColors = {
  color: string;
  shadowColor: string;
  disabledColor: string;
  disabledShadowColor: string;
};

export const ButtonColors: Record<string, DepthColors> = {
  Default: {
    color: AppColors.Gray,
    shadowColor: AppColors.GrayShadow,
    disabledColor: AppColors.GrayShadow,
    disabledShadowColor: AppColors.GrayShadow,
  },
  ProgressGreen: {
    color: AppColors.Green,
    shadowColor: AppColors.GreenShadow,
    disabledColor: "#52811A",
    disabledShadowColor: "#273C12",
  },
  DeclineRed: {
    color: AppColors.Red,
    shadowColor: AppColors.RedShadow,
    disabledColor: "#590707",
    disabledShadowColor: "#430404",
  },
  MessagePurple: {
    color: AppColors.Purple,
    shadowColor: AppColors.PurpleShadow,
    disabledColor: "#5E0753",
    disabledShadowColor: "#33032D",
  },
  UploadOrange: {
    color: AppColors.Orange,
    shadowColor: AppColors.OrangeShadow,
    disabledColor: AppColors.GrayShadow,
    disabledShadowColor: AppColors.GrayShadow,
  },
};
