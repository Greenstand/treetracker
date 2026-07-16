import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import type { RouteProp } from "@react-navigation/native";

export type RootStackParamList = {
  Splash: undefined;
  Language: undefined;
  Credential: undefined;
  Name: undefined;
  Selfie: undefined;
  ImageReview: { photoUri: string };
  Dashboard: undefined;
  UserSelect: undefined;
  WalletSelect: { userUuid: string };
  AddOrg: { userUuid: string; wallet: string };
  TreeCapture: { sessionId: string };
  TreeImageReview: {
    sessionId: string;
    photoUri: string;
    lat: number;
    lon: number;
  };
};

export type Nav<T extends keyof RootStackParamList> = NativeStackNavigationProp<
  RootStackParamList,
  T
>;
export type Rt<T extends keyof RootStackParamList> = RouteProp<
  RootStackParamList,
  T
>;
