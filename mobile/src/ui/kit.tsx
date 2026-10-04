import { type ReactNode, useState } from 'react';
import {
  KeyboardAvoidingView,
  Modal,
  Pressable,
  ScrollView,
  type StyleProp,
  StyleSheet,
  Text,
  TextInput,
  type TextStyle,
  View,
  type ViewStyle,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useTheme } from './theme';

/** A tab's root: safe-area aware, scrolling by default. */
export function Screen({ title, children, scroll = true }: { title?: string; children: ReactNode; scroll?: boolean }) {
  const theme = useTheme();
  const heading = title ? <Text style={[styles.screenTitle, { color: theme.text }]}>{title}</Text> : null;
  return (
    <SafeAreaView style={[styles.flex, { backgroundColor: theme.background }]} edges={['top', 'left', 'right']}>
      {scroll ? (
        <ScrollView contentContainerStyle={styles.screenContent} keyboardShouldPersistTaps="handled">
          {heading}
          {children}
        </ScrollView>
      ) : (
        <View style={styles.flex}>
          {heading ? <View style={styles.fixedHeading}>{heading}</View> : null}
          {children}
        </View>
      )}
    </SafeAreaView>
  );
}

export function SectionTitle({ children }: { children: ReactNode }) {
  const theme = useTheme();
  return <Text style={[styles.sectionTitle, { color: theme.secondary }]}>{children}</Text>;
}

export function Card({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  const theme = useTheme();
  return <View style={[styles.card, { backgroundColor: theme.card }, style]}>{children}</View>;
}

export function Divider() {
  const theme = useTheme();
  return <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: theme.border }} />;
}

export function Body({ children, style, secondary }: { children: ReactNode; style?: StyleProp<TextStyle>; secondary?: boolean }) {
  const theme = useTheme();
  return <Text style={[styles.body, { color: secondary ? theme.secondary : theme.text }, style]}>{children}</Text>;
}

type ButtonKind = 'primary' | 'secondary' | 'plain' | 'danger';

export function Button({
  label,
  onPress,
  kind = 'primary',
  disabled,
  testID,
  compact,
}: {
  label: string;
  onPress: () => void;
  kind?: ButtonKind;
  disabled?: boolean;
  testID?: string;
  compact?: boolean;
}) {
  const theme = useTheme();
  const filled = kind === 'primary';
  const color = kind === 'danger' ? theme.danger : filled ? theme.onAccent : theme.accent;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      testID={testID}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        compact && styles.buttonCompact,
        filled && { backgroundColor: theme.accent },
        (kind === 'secondary' || kind === 'danger') && { borderWidth: 1, borderColor: kind === 'danger' ? theme.danger : theme.accent },
        { opacity: disabled ? 0.4 : pressed ? 0.6 : 1 },
      ]}>
      <Text style={[styles.buttonLabel, compact && styles.buttonLabelCompact, { color }]}>{label}</Text>
    </Pressable>
  );
}

/** A row that reads as tappable: content on the left, optional trailing text. */
export function Row({ children, onPress, trailing, testID }: { children: ReactNode; onPress?: () => void; trailing?: ReactNode; testID?: string }) {
  const theme = useTheme();
  const content = (
    <View style={styles.row}>
      <View style={styles.flex}>{children}</View>
      {typeof trailing === 'string' ? <Text style={[styles.body, { color: theme.accent }]}>{trailing}</Text> : trailing}
    </View>
  );
  if (!onPress) return content;
  return (
    <Pressable accessibilityRole="button" testID={testID} onPress={onPress} style={({ pressed }) => ({ opacity: pressed ? 0.6 : 1 })}>
      {content}
    </Pressable>
  );
}

export function Segmented<T extends string | number>({ options, value, onChange }: { options: { label: string; value: T }[]; value: T; onChange: (value: T) => void }) {
  const theme = useTheme();
  return (
    <View style={[styles.segmented, { backgroundColor: theme.background, borderColor: theme.border }]}>
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={String(option.value)}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={option.label}
            onPress={() => onChange(option.value)}
            style={[styles.segment, selected && { backgroundColor: theme.accent }]}>
            <Text style={[styles.segmentLabel, { color: selected ? theme.onAccent : theme.text }]}>{option.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Stepper({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (value: number) => void }) {
  const theme = useTheme();
  const step = (delta: number, name: string) => (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={name}
      disabled={value + delta < min || value + delta > max}
      onPress={() => onChange(value + delta)}
      style={({ pressed }) => [styles.stepButton, { borderColor: theme.border, opacity: value + delta < min || value + delta > max ? 0.3 : pressed ? 0.6 : 1 }]}>
      <Text style={[styles.stepLabel, { color: theme.accent }]}>{delta > 0 ? '+' : '−'}</Text>
    </Pressable>
  );
  return (
    <View style={styles.stepper}>
      <Text style={[styles.body, styles.flex, { color: theme.text }]}>{label}</Text>
      {step(-1, `Decrease ${label}`)}
      {step(1, `Increase ${label}`)}
    </View>
  );
}

export interface SheetOption {
  label: string;
  onPress: () => void;
  destructive?: boolean;
  selected?: boolean;
}

/** A bottom sheet of choices — the cross-platform stand-in for a pull-down menu. */
export function OptionSheet({ visible, title, options, onClose }: { visible: boolean; title: string; options: SheetOption[]; onClose: () => void }) {
  const theme = useTheme();
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={[styles.scrim, { backgroundColor: theme.scrim }]} onPress={onClose} accessibilityLabel="Dismiss">
        <Pressable style={[styles.sheet, { backgroundColor: theme.card }]} onPress={() => {}}>
          <Text style={[styles.sheetTitle, { color: theme.secondary }]}>{title}</Text>
          <ScrollView style={styles.sheetList}>
            {options.map((option, index) => (
              <Pressable
                key={`${index}-${option.label}`}
                accessibilityRole="button"
                accessibilityLabel={option.label}
                onPress={() => {
                  onClose();
                  option.onPress();
                }}
                style={({ pressed }) => [styles.sheetOption, { borderTopColor: theme.border, opacity: pressed ? 0.6 : 1 }]}>
                <Text style={[styles.sheetOptionLabel, { color: option.destructive ? theme.danger : theme.text, fontWeight: option.selected ? '700' : '400' }]}>
                  {option.label}
                  {option.selected ? '  ✓' : ''}
                </Text>
              </Pressable>
            ))}
          </ScrollView>
          <Button label="Cancel" kind="plain" onPress={onClose} />
        </Pressable>
      </Pressable>
    </Modal>
  );
}

interface TextPromptProps {
  visible: boolean;
  title: string;
  initialText: string;
  placeholder?: string;
  multiline?: boolean;
  onSave: (text: string) => void;
  onClose: () => void;
}

/** A small dialog for editing one piece of text (notes, names) with Cancel / Save. */
export function TextPrompt(props: TextPromptProps) {
  const theme = useTheme();
  return (
    <Modal visible={props.visible} transparent animationType="fade" onRequestClose={props.onClose}>
      <KeyboardAvoidingView behavior="padding" style={[styles.scrim, styles.centered, { backgroundColor: theme.scrim }]}>
        {/* Mounted per showing, so each time it opens the draft starts from the current text. */}
        {props.visible ? <TextPromptDialog {...props} /> : null}
      </KeyboardAvoidingView>
    </Modal>
  );
}

function TextPromptDialog({ title, initialText, placeholder, multiline = true, onSave, onClose }: TextPromptProps) {
  const theme = useTheme();
  const [text, setText] = useState(initialText);
  return (
    <View style={[styles.dialog, { backgroundColor: theme.card }]}>
      <Text style={[styles.dialogTitle, { color: theme.text }]}>{title}</Text>
      <TextInput
        testID="textPromptInput"
        accessibilityLabel={title}
        value={text}
        onChangeText={setText}
        placeholder={placeholder}
        placeholderTextColor={theme.tertiary}
        multiline={multiline}
        autoFocus
        style={[styles.dialogInput, multiline && styles.dialogInputMultiline, { color: theme.text, borderColor: theme.border }]}
      />
      <View style={styles.dialogButtons}>
        <Button label="Cancel" kind="plain" onPress={onClose} compact />
        <Button
          label="Save"
          onPress={() => {
            onSave(text);
            onClose();
          }}
          compact
        />
      </View>
    </View>
  );
}

export function EmptyState({ title, message, children }: { title: string; message: string; children?: ReactNode }) {
  const theme = useTheme();
  return (
    <View style={styles.empty}>
      <Text style={[styles.emptyTitle, { color: theme.text }]}>{title}</Text>
      <Text style={[styles.body, styles.emptyMessage, { color: theme.secondary }]}>{message}</Text>
      {children}
    </View>
  );
}

export const styles = StyleSheet.create({
  flex: { flex: 1 },
  screenContent: { padding: 16, paddingBottom: 120, gap: 12 },
  fixedHeading: { paddingHorizontal: 16, paddingTop: 16 },
  screenTitle: { fontSize: 30, fontWeight: '700', marginBottom: 4 },
  sectionTitle: { fontSize: 13, fontWeight: '600', textTransform: 'uppercase', letterSpacing: 0.4, marginTop: 12, marginLeft: 4 },
  card: { borderRadius: 14, paddingHorizontal: 14, paddingVertical: 4 },
  body: { fontSize: 16, lineHeight: 22 },
  button: { minHeight: 48, borderRadius: 12, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16 },
  buttonCompact: { minHeight: 40, paddingHorizontal: 14 },
  buttonLabel: { fontSize: 17, fontWeight: '600' },
  buttonLabelCompact: { fontSize: 15 },
  row: { flexDirection: 'row', alignItems: 'center', minHeight: 48, paddingVertical: 8, gap: 12 },
  segmented: { flexDirection: 'row', borderRadius: 10, borderWidth: StyleSheet.hairlineWidth, overflow: 'hidden' },
  segment: { flex: 1, minHeight: 40, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8 },
  segmentLabel: { fontSize: 15, fontWeight: '600' },
  stepper: { flexDirection: 'row', alignItems: 'center', gap: 8, minHeight: 48 },
  stepButton: { width: 44, height: 40, borderRadius: 10, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
  stepLabel: { fontSize: 22, fontWeight: '500' },
  scrim: { flex: 1, justifyContent: 'flex-end' },
  centered: { justifyContent: 'center', padding: 24 },
  sheet: { borderTopLeftRadius: 18, borderTopRightRadius: 18, paddingTop: 14, paddingBottom: 28, paddingHorizontal: 8, maxHeight: '75%' },
  sheetTitle: { fontSize: 13, fontWeight: '600', textAlign: 'center', marginBottom: 8 },
  sheetList: { flexGrow: 0 },
  sheetOption: { minHeight: 52, justifyContent: 'center', paddingHorizontal: 16, borderTopWidth: StyleSheet.hairlineWidth },
  sheetOptionLabel: { fontSize: 17 },
  dialog: { borderRadius: 16, padding: 18, gap: 12 },
  dialogTitle: { fontSize: 18, fontWeight: '600' },
  dialogInput: { borderWidth: 1, borderRadius: 10, padding: 10, fontSize: 16 },
  dialogInputMultiline: { minHeight: 110, textAlignVertical: 'top' },
  dialogButtons: { flexDirection: 'row', justifyContent: 'flex-end', gap: 8 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32, gap: 12 },
  emptyTitle: { fontSize: 24, fontWeight: '700', textAlign: 'center' },
  emptyMessage: { textAlign: 'center' },
});
