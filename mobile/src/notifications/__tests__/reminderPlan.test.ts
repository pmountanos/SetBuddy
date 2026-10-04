import { calendarDate } from '../../domain/calendarDate';
import { ProgramCalendarSchedule, REST, workoutPlan } from '../../domain/schedule';
import { clampReminderPrefs, planReminders } from '../reminderPlan';

const today = calendarDate(2026, 10, 5);
const titles = new Map([['w1', 'Push 1']]);

function schedule() {
  const s = new ProgramCalendarSchedule();
  s.set(calendarDate(2026, 10, 5), workoutPlan('w1'));
  s.set(calendarDate(2026, 10, 6), REST);
  s.set(calendarDate(2026, 10, 7), workoutPlan('gone'));
  return s;
}

describe('planReminders', () => {
  it('plans nothing when reminders are off', () => {
    expect(planReminders({ prefs: { enabled: false, hour: 8, minute: 0 }, today, now: new Date(2026, 9, 5, 7), schedule: schedule(), workoutTitles: titles })).toEqual([]);
  });

  it('plans one reminder per day at the chosen local time, describing that day', () => {
    const planned = planReminders({ prefs: { enabled: true, hour: 8, minute: 30 }, today, now: new Date(2026, 9, 5, 7), schedule: schedule(), workoutTitles: titles });
    expect(planned).toHaveLength(14);
    expect(planned.slice(0, 4).map((r) => [r.id, r.title, r.body])).toEqual([
      ['net.mountanos.setbuddy.schedule.2026-10-5', 'Workout day', 'Today: Push 1.'],
      ['net.mountanos.setbuddy.schedule.2026-10-6', 'Rest day', 'Today is a scheduled rest day.'],
      ['net.mountanos.setbuddy.schedule.2026-10-7', 'Workout day', 'Today: Workout.'],
      ['net.mountanos.setbuddy.schedule.2026-10-8', 'Set Buddy', 'Open the app to see your plan.'],
    ]);
    expect(planned[0].fireAt).toEqual(new Date(2026, 9, 5, 8, 30));
    expect(planned[13].fireAt).toEqual(new Date(2026, 9, 18, 8, 30));
  });

  it("skips today's reminder once its time has passed", () => {
    const planned = planReminders({ prefs: { enabled: true, hour: 8, minute: 0 }, today, now: new Date(2026, 9, 5, 8, 0), schedule: schedule(), workoutTitles: titles });
    expect(planned).toHaveLength(13);
    expect(planned[0].title).toBe('Rest day');
  });

  it('prompts to set up a program when there is none', () => {
    const planned = planReminders({ prefs: { enabled: true, hour: 8, minute: 0 }, today, now: new Date(2026, 9, 5, 7), schedule: null, workoutTitles: new Map(), horizonDays: 1 });
    expect(planned).toMatchObject([{ title: 'Set Buddy', body: 'Set up your training program in the app.' }]);
  });

  it('keeps the time within a real clock', () => {
    expect(clampReminderPrefs({ enabled: true, hour: 99, minute: -5 })).toEqual({ enabled: true, hour: 23, minute: 0 });
    expect(clampReminderPrefs({ enabled: true, hour: NaN, minute: 30.9 })).toEqual({ enabled: true, hour: 0, minute: 30 });
  });
});
