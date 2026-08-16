// kind: form-field
// Role: the brand-asset dropzone — a labelled file input styled as a
//   drop target (pure CSS: the dashed region IS the label), plus the
//   seeded asset list under it. The POST is the same acknowledgement as
//   every design-medium trigger.
// Requirements: Q-v2-1, Q-v2-5 (inspect triple + annotation quad).
// Relationships: composed by all three studio_intake_view.<factor>.tsx
//   variants; posts to /intake/upload.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import type { UploadAsset } from '../../views/studio_intake_shell/studio_intake/studio_intake_view.desktop.tsx';

export interface AssetUploadDropzoneProps {
  title: string;
  hint: string;
  button: string;
  assets: UploadAsset[];
  /** inside the mobile disclosure: tighter spacing, smaller list */
  compact?: boolean;
}

const AssetUploadDropzone: FC<AssetUploadDropzoneProps> = ({ title, hint, button, assets, compact }) => (
  <section
    class={compact ? 'asset-drop asset-drop--compact' : 'asset-drop'}
    aria-labelledby="asset-drop-h"
    data-el="form-field"
    data-inspect-widget="asset_upload_dropzone"
    data-inspect-role="form"
    data-inspect-style="dashed drop target over the uploaded asset list"
    data-inspect-fn="collects the brand assets the brief needs"
    data-inspect-motion="none"
  >
    <h2
      id="asset-drop-h"
      class="asset-drop-title"
      data-inspect-role="heading"
      data-inspect-style="small section heading"
      data-inspect-fn="names the upload section"
      data-inspect-motion="none"
    >
      {title}
    </h2>
    <form
      class="asset-drop-zone"
      method="post"
      action="/intake/upload"
      enctype="multipart/form-data"
      data-el="form-field__body"
      data-inspect-role="form"
      data-inspect-style="dashed region wrapping a hidden file input and a browse trigger"
      data-inspect-fn="receives dropped or browsed brand assets"
      data-inspect-motion="pending"
    >
      <input
        type="file"
        name="asset"
        multiple
        aria-label={button}
        data-el="form-field__input"
        data-inspect-role="input"
        data-inspect-style="file input rendered as the dashed drop region"
        data-inspect-fn="holds the selected assets"
        data-inspect-motion="none"
      />
      <Icon
        name="upload"
        size={22}
      />
      <p
        class="asset-drop-hint muted"
        data-inspect-role="text"
        data-inspect-style="one hint line inside the dashed region"
        data-inspect-fn="says what kinds of assets belong here"
        data-inspect-motion="none"
      >
        {hint}
      </p>
      <button type="submit" class="btn">
        {button}
      </button>
    </form>
    {assets.length > 0 && (
      <ul
        class="asset-list"
        data-el="list-row__item"
        data-inspect-role="list"
        data-inspect-style="uploaded assets as name + kind + size rows"
        data-inspect-fn="shows what the dropzone already collected"
        data-inspect-motion="reveal"
      >
        {assets.map((asset) => (
          <li key={asset.id} class="asset-row">
            <span class="asset-name">{asset.name}</span>
            <span class="asset-kind muted">{asset.kind}</span>
            <span class="asset-size muted">{asset.size}</span>
          </li>
        ))}
      </ul>
    )}
  </section>
);

export default AssetUploadDropzone;
