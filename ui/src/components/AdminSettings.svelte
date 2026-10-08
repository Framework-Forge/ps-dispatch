<script lang="ts">
  import { ADMIN_OPEN, ADMIN_PAYLOAD, CREATED_ZONE, OVERLAY_OPEN } from '@store/stores';
  import { SendNUI } from '@utils/SendNUI';
  import { fade, scale } from 'svelte/transition';

  let config: any = null;
  let tab = 'general';
  let saving = false;
  let status = '';
  let statusType = '';
  let advanced = '';
  let zoneName = 'Área sem despacho';
  let pendingShape = '';
  let lastPayload: any = null;
  let lastCreated: any = null;
  const clone = (value: any) => JSON.parse(JSON.stringify(value || {}));

  $: OVERLAY_OPEN.set($ADMIN_OPEN);
  $: if ($ADMIN_OPEN && $ADMIN_PAYLOAD !== lastPayload) {
    lastPayload = $ADMIN_PAYLOAD;
    config = clone($ADMIN_PAYLOAD?.config);
    ensureShape();
    advanced = JSON.stringify(config, null, 2);
  }
  $: if ($CREATED_ZONE && $CREATED_ZONE !== lastCreated) {
    lastCreated = $CREATED_ZONE;
    if (pendingShape) {
      const created = $CREATED_ZONE.value;
      if (created && config) {
        const list = config.Locations.NoDispatchZones;
        list.push({
          ...created,
          id: `dispatch-${Date.now()}`,
          label: zoneName.trim() || 'Área sem despacho',
          active: true,
        });
        // Reassign the root so Svelte refreshes the keyed zone list as soon
        // as the world editor returns. Mutating the nested array alone is not
        // observable by the compiled component.
        config = { ...config };
        status = 'Área adicionada. Clique em Salvar para publicar.';
        statusType = 'success';
        advanced = JSON.stringify(config, null, 2);
      } else {
        status = 'Criação da área cancelada.';
        statusType = 'error';
      }
      pendingShape = '';
    }
  }

  function ensureShape() {
    if (!config.Locations) config.Locations = {};
    if (!Array.isArray(config.Locations.NoDispatchZones)) config.Locations.NoDispatchZones = [];
    if (!Array.isArray(config.Locations.HuntingZones)) config.Locations.HuntingZones = [];
    if (!config.SafeZoneIntegration) config.SafeZoneIntegration = { Enabled: false, Resource: 'forge-smallresources', IncludeTypes: { safezone: true } };
    if (!config.SafeZoneIntegration.IncludeTypes) config.SafeZoneIntegration.IncludeTypes = { safezone: true };
  }

  $: jobOptions = (() => {
    const listed = Array.isArray($ADMIN_PAYLOAD?.jobs) ? $ADMIN_PAYLOAD.jobs : [];
    const known = new Set(listed.map((job: any) => job.name));
    const preserved = (config?.Jobs || [])
      .filter((name: string) => !known.has(name))
      .map((name: string) => ({ name, label: name, type: 'categoria configurada' }));
    return [...listed, ...preserved];
  })();

  function toggleJob(name: string) {
    const selected = new Set(Array.isArray(config.Jobs) ? config.Jobs : []);
    selected.has(name) ? selected.delete(name) : selected.add(name);
    config.Jobs = Array.from(selected);
    config = { ...config };
    advanced = JSON.stringify(config, null, 2);
  }
  function numeric(key: string, value: string) { config[key] = Number(value); }

  async function createZone(shape: string) {
    pendingShape = shape;
    status = 'Use o editor 3D e pressione Enter para salvar a geometria.';
    statusType = '';
    const response: any = await SendNUI('createDispatchZone', {
      shape,
      radius: 20,
      thickness: 4,
    });
    if (!response?.ok) {
      pendingShape = '';
      status = response?.error || 'Não foi possível abrir o editor.';
      statusType = 'error';
    }
  }

  function removeZone(index: number) {
    config.Locations.NoDispatchZones.splice(index, 1);
    config = { ...config };
    advanced = JSON.stringify(config, null, 2);
  }

  function applyAdvanced() {
    try {
      config = JSON.parse(advanced);
      ensureShape();
      status = 'JSON aplicado localmente. Clique em Salvar para publicar.';
      statusType = 'success';
    } catch (error) {
      status = 'JSON inválido. Revise vírgulas, chaves e valores.';
      statusType = 'error';
    }
  }

  async function save() {
    saving = true;
    status = '';
    const response: any = await SendNUI('saveDispatchAdminConfig', config);
    saving = false;
    if (response?.ok) {
      ADMIN_PAYLOAD.set(response);
      config = clone(response.config);
      ensureShape();
      advanced = JSON.stringify(config, null, 2);
      status = 'Configuração publicada para todos os jogadores.';
      statusType = 'success';
    } else {
      status = response?.error || 'Não foi possível salvar.';
      statusType = 'error';
    }
  }
</script>

{#if $ADMIN_OPEN && config}
  <div class="pd-modal-overlay pd-admin-overlay" on:click|self={() => ADMIN_OPEN.set(false)} transition:fade={{ duration: 120 }}>
    <section class="pd-admin" in:scale={{ start: .97, duration: 160 }}>
      <header class="pd-admin-head">
        <div class="pd-brand-mark"><i class="fas fa-tower-broadcast"></i></div>
        <div>
          <span class="pd-admin-eyebrow">FORGEBOX · CENTRAL DE OPERAÇÕES</span>
          <h2>Configuração do Dispatch</h2>
        </div>
        <span class="pd-live"><i></i> Sincronizado</span>
        <button class="pd-ctl" on:click={() => ADMIN_OPEN.set(false)}><i class="fas fa-xmark"></i></button>
      </header>

      <nav class="pd-admin-tabs">
        <button class:active={tab === 'general'} on:click={() => tab = 'general'}><i class="fas fa-sliders"></i> Geral</button>
        <button class:active={tab === 'zones'} on:click={() => tab = 'zones'}><i class="fas fa-draw-polygon"></i> Áreas ignoradas</button>
        <button class:active={tab === 'advanced'} on:click={() => tab = 'advanced'}><i class="fas fa-code"></i> Avançado</button>
      </nav>

      <div class="pd-admin-body pd-scroll">
        {#if tab === 'general'}
          <div class="pd-admin-grid">
            <label><span>Duração do alerta</span><small>Segundos na tela</small><input type="number" min="1" max="120" value={config.AlertTime} on:input={(e) => numeric('AlertTime', e.currentTarget.value)} /></label>
            <label><span>Chamados no histórico</span><small>Máximo exibido</small><input type="number" min="1" max="250" value={config.MaxCallList} on:input={(e) => numeric('MaxCallList', e.currentTarget.value)} /></label>
            <label><span>Alertas simultâneos</span><small>Pilhas na interface</small><input type="number" min="1" max="20" value={config.MaxVisibleAlerts} on:input={(e) => numeric('MaxVisibleAlerts', e.currentTarget.value)} /></label>
            <label><span>Expiração do chamado</span><small>Minutos; zero desativa</small><input type="number" min="0" max="1440" value={config.CallLifetime} on:input={(e) => numeric('CallLifetime', e.currentTarget.value)} /></label>
          </div>
          <section class="pd-jobs">
            <div class="pd-jobs-head">
              <div><b>Empregos autorizados</b><span>Selecione quem pode receber e acessar os chamados</span></div>
              <em>{config.Jobs?.length || 0} selecionados</em>
            </div>
            <div class="pd-jobs-grid pd-scroll">
              {#each jobOptions as job (job.name)}
                <label class:checked={config.Jobs?.includes(job.name)}>
                  <input type="checkbox" checked={config.Jobs?.includes(job.name)} on:change={() => toggleJob(job.name)} />
                  <i class="fas fa-briefcase"></i>
                  <div><b>{job.label}</b><span>{job.name}{job.type ? ` · ${job.type}` : ''}</span></div>
                  <i class="fas fa-check check"></i>
                </label>
              {:else}
                <div class="pd-empty pd-jobs-empty"><b>Nenhum emprego cadastrado</b><span>O PR Bridge não retornou empregos da framework.</span></div>
              {/each}
            </div>
          </section>
          <div class="pd-admin-cards">
            <button class="pd-choice" class:on={config.FilteredBroadcast === true} on:click={() => config.FilteredBroadcast = !config.FilteredBroadcast}><i class="fas fa-satellite-dish"></i><div><b>Filtro no servidor</b><span>Envia somente aos empregos elegíveis</span></div><em>{config.FilteredBroadcast ? 'ATIVO' : 'INATIVO'}</em></button>
            <button class="pd-choice" class:on={config.FilterOnDuty === true} on:click={() => config.FilterOnDuty = !config.FilterOnDuty}><i class="fas fa-user-shield"></i><div><b>Somente em serviço</b><span>Ignora agentes fora de serviço</span></div><em>{config.FilterOnDuty ? 'ATIVO' : 'INATIVO'}</em></button>
            <button class="pd-choice" class:on={config.PhoneRequired === true} on:click={() => config.PhoneRequired = !config.PhoneRequired}><i class="fas fa-mobile-screen"></i><div><b>Telefone obrigatório</b><span>Exige telefone para 190/911</span></div><em>{config.PhoneRequired ? 'ATIVO' : 'INATIVO'}</em></button>
          </div>
        {:else if tab === 'zones'}
          <div class="pd-zone-intro">
            <div><h3>Áreas sem despacho</h3><p>Dentro destas áreas, alertas automáticos são ignorados. Polígonos usam o mesmo editor 3D das Safe Zones.</p></div>
            <span>{config.Locations.NoDispatchZones.length} próprias · {$ADMIN_PAYLOAD.externalZones?.length || 0} vinculadas</span>
          </div>
          <div class="pd-safe-link">
            <div class="pd-safe-icon"><i class="fas fa-shield-halved"></i></div>
            <div><b>Usar Safe Zones do Forge Small Resources</b><span>Sincroniza polígonos e círculos ativos como áreas sem alertas. A integração é opcional.</span></div>
            <button class="pd-toggle" class:pd-toggle--on={config.SafeZoneIntegration.Enabled === true} on:click={() => config.SafeZoneIntegration.Enabled = !config.SafeZoneIntegration.Enabled}></button>
          </div>
          <div class="pd-zone-create">
            <input bind:value={zoneName} maxlength="64" placeholder="Nome da área" />
            <button class="pd-btn" disabled={!!pendingShape} on:click={() => createZone('sphere')}><i class="fas fa-circle-dot"></i> Novo círculo</button>
            <button class="pd-btn pd-btn--primary" disabled={!!pendingShape} on:click={() => createZone('poly')}><i class="fas fa-draw-polygon"></i> Novo polígono</button>
          </div>
          <div class="pd-zone-list">
            {#each config.Locations.NoDispatchZones as zone, index}
              <article>
                <div class="pd-zone-shape"><i class="fas fa-{zone.shape === 'poly' ? 'draw-polygon' : zone.shape === 'sphere' ? 'circle-dot' : 'vector-square'}"></i></div>
                <div><b>{zone.label || zone.name}</b><span>{zone.shape || 'box'} · {zone.shape === 'poly' ? `${zone.points?.length || 0} pontos` : zone.shape === 'sphere' ? `${zone.radius || 0} m` : `${zone.length || 0} × ${zone.width || 0} m`}</span></div>
                <button class="pd-toggle pd-toggle--sm" class:pd-toggle--on={zone.active !== false} on:click={() => { zone.active = zone.active === false; config = {...config}; }}></button>
                <button class="pd-icon-danger" on:click={() => removeZone(index)}><i class="fas fa-trash"></i></button>
              </article>
            {:else}
              <div class="pd-empty"><i class="fas fa-location-crosshairs"></i><b>Nenhuma área própria</b><span>Crie um círculo ou polígono diretamente no mundo.</span></div>
            {/each}
          </div>
        {:else}
          <div class="pd-code-head"><div><h3>Configuração completa</h3><p>Blips, cores, sons, scanner e demais opções avançadas.</p></div><button class="pd-btn" on:click={applyAdvanced}><i class="fas fa-check"></i> Aplicar JSON</button></div>
          <textarea class="pd-json" bind:value={advanced} spellcheck="false"></textarea>
        {/if}
      </div>

      <footer class="pd-admin-foot">
        <span class:success={statusType === 'success'} class:error={statusType === 'error'}>{status}</span>
        <button class="pd-btn" on:click={() => ADMIN_OPEN.set(false)}>Fechar</button>
        <button class="pd-btn pd-btn--primary" disabled={saving} on:click={save}><i class="fas fa-cloud-arrow-up"></i> {saving ? 'Salvando…' : 'Salvar e publicar'}</button>
      </footer>
    </section>
  </div>
{/if}
