import { describe, expect, it } from 'bun:test'
import {
  type MochiState,
  type EyeShape,
  type AgentInfo,
  type ApprovalRequest,
  type SystemState,
  getEyeShape,
  getGlowColor,
  hexToRgba,
} from '../src/lib/types/agent'
import MochiBot from '../src/lib/components/MochiBot.svelte'
import MiniMochi from '../src/lib/components/MiniMochi.svelte'

describe('Mochi Companion Engine', () => {
  it('correctly maps official glow colors per state from MochiBot.qml', () => {
    expect(getGlowColor('working')).toBe('#3B9EFF')
    expect(getGlowColor('thinking')).toBe('#A78BFA')
    expect(getGlowColor('searching')).toBe('#6366F1')
    expect(getGlowColor('approval')).toBe('#F5A524')
    expect(getGlowColor('question')).toBe('#22D3EE')
    expect(getGlowColor('error')).toBe('#F4505E')
    expect(getGlowColor('finished')).toBe('#34D399')
    expect(getGlowColor('done')).toBe('#34D399')
    expect(getGlowColor('ratelimit')).toBe('#F59E0B')
    expect(getGlowColor('sleeping')).toBe('#94A3B8')
    expect(getGlowColor('dizzy')).toBe('#EC4899')
    expect(getGlowColor('idle', '#4ADE80')).toBe('#4ADE80')
    expect(getGlowColor('idle', '#FF0055')).toBe('#FF0055')
  })

  it('correctly maps eye shapes per state from MochiBot.qml', () => {
    expect(getEyeShape('idle')).toBe('pill')
    expect(getEyeShape('working')).toBe('pill')
    expect(getEyeShape('searching')).toBe('pill')
    expect(getEyeShape('question')).toBe('pill')
    expect(getEyeShape('thinking')).toBe('wide')
    expect(getEyeShape('approval')).toBe('wide')
    expect(getEyeShape('finished')).toBe('happy')
    expect(getEyeShape('done')).toBe('happy')
    expect(getEyeShape('sleeping')).toBe('closed')
    expect(getEyeShape('error')).toBe('flat')
    expect(getEyeShape('ratelimit')).toBe('flat')
    expect(getEyeShape('dizzy')).toBe('dizzy')
  })

  it('supports all 6 official eye shapes', () => {
    const shapes: EyeShape[] = ['pill', 'wide', 'happy', 'closed', 'flat', 'dizzy']
    expect(shapes).toHaveLength(6)
  })

  it('triggers dizzy eye shape on easter-egg triple tap (clickCount >= 3)', () => {
    expect(getEyeShape('idle', 0)).toBe('pill')
    expect(getEyeShape('idle', 1)).toBe('pill')
    expect(getEyeShape('idle', 2)).toBe('pill')
    expect(getEyeShape('idle', 3)).toBe('dizzy')
    expect(getEyeShape('idle', 4)).toBe('dizzy')
    expect(getEyeShape('working', 3)).toBe('dizzy')
    expect(getEyeShape('approval', 3)).toBe('dizzy')
  })

  it('converts hex colors to rgba properly', () => {
    expect(hexToRgba('#4ADE80', 0.32)).toBe('rgba(74, 222, 128, 0.32)')
    expect(hexToRgba('#FFF', 0.5)).toBe('rgba(255, 255, 255, 0.5)')
    expect(hexToRgba('#181412', 0.9)).toBe('rgba(24, 20, 18, 0.9)')
    expect(hexToRgba('rgb(0,0,0)', 0.5)).toBe('rgb(0,0,0)')
  })

  it('exports valid component definitions and types', () => {
    expect(MochiBot).toBeDefined()
    expect(MiniMochi).toBeDefined()

    const agent: AgentInfo = {
      name: 'caelestia-coder',
      command: 'bun run dev',
      pid: 1234,
      status: 'working',
      cpu: 12.5,
      memory: 45.2,
    }
    expect(agent.name).toBe('caelestia-coder')

    const approval: ApprovalRequest = {
      approval_id: 'appr-1234abcd',
      session_id: 'ses-1',
      command: 'rm -rf /tmp/test',
      prompt: 'Execute command? (y/n)',
      approved: false,
    }
    expect(approval.approval_id).toBe('appr-1234abcd')

    const system: SystemState = {
      timestamp: Date.now(),
      agents: [agent],
      active_agent: agent,
      mochi_state: 'working',
    }
    expect(system.mochi_state).toBe('working')
  })
})
