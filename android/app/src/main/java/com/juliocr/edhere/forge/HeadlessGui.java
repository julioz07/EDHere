package com.juliocr.edhere.forge;

import java.io.File;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.function.Consumer;

import org.jupnp.UpnpServiceConfiguration;

import forge.gamemodes.match.HostedMatch;
import forge.gui.download.GuiDownloadService;
import forge.gui.interfaces.IGuiBase;
import forge.gui.interfaces.IGuiGame;
import forge.item.PaperCard;
import forge.localinstance.skin.FSkinProp;
import forge.localinstance.skin.ISkinImage;
import forge.sound.IAudioClip;
import forge.sound.IAudioMusic;
import forge.util.FSerializableFunction;
import forge.util.ImageFetcher;

/**
 * O Forge sem interface própria: a mesa é desenhada pelo Flutter. Baseado em
 * forge-gui/tools/java/ForgeMatrixWriter.java do Forge.
 */
final class HeadlessGui implements IGuiBase {
    private final String assetsDir;

    HeadlessGui(String assetsDir) {
        this.assetsDir = assetsDir.endsWith("/") ? assetsDir : assetsDir + "/";
    }

    // "desktop" para o Forge usar as pastas do forge.profile.properties
    @Override public boolean isRunningOnDesktop() { return true; }
    @Override public boolean isLibgdxPort() { return false; }
    @Override public String getCurrentVersion() { return "edhere"; }
    @Override public String getUserAgent() { return "Forge (EDHere)"; }
    @Override public void invokeInEdtNow(Runnable r) { r.run(); }
    @Override public void invokeInEdtLater(Runnable r) { r.run(); }
    @Override public void invokeInEdtAndWait(Runnable r) { r.run(); }
    @Override public void runBackgroundTask(String message, Runnable task) { task.run(); }
    @Override public boolean isGuiThread() { return true; }
    @Override public String getAssetsDir() { return assetsDir; }
    @Override public ImageFetcher getImageFetcher() { return null; }
    @Override public ISkinImage getSkinIcon(FSkinProp p) { return null; }
    @Override public ISkinImage getUnskinnedIcon(String path) { return null; }
    @Override public ISkinImage getCardArt(PaperCard card, boolean backFace) { return null; }
    @Override public ISkinImage createLayeredImage(PaperCard card, FSkinProp bg, String overlay, float opacity) { return null; }
    @Override public void clearImageCache() { }
    @Override public String encodeSymbols(String str, boolean formatReminderText) { return str; }
    @Override public int getAvatarCount() { return 0; }
    @Override public int getSleevesCount() { return 0; }
    @Override public float getScreenScale() { return 1f; }
    @Override public void preventSystemSleep(boolean b) { }
    @Override public void download(GuiDownloadService s, Consumer<Boolean> cb) { cb.accept(false); }
    @Override public void copyToClipboard(String text) { }
    @Override public void browseToUrl(String url) { }
    @Override public void showCardList(String t, String m, List<PaperCard> l) { }
    @Override public boolean showBoxedProduct(String t, String m, List<PaperCard> l) { return false; }
    @Override public void showBugReportDialog(String t, String text, boolean exit) { ForgeEngine.log("bug: " + t + "\n" + text); }
    @Override public void showImageDialog(ISkinImage i, String m, String t) { }
    @Override public int showOptionDialog(String m, String t, FSkinProp i, List<String> o, int def) { return def; }
    @Override public String showInputDialog(String m, String t, FSkinProp i, String init, List<String> o, boolean n) { return init; }
    @Override public String showFileDialog(String t, String d) { return d; }
    @Override public File getSaveFile(File f) { return f; }
    @Override public <T> List<T> order(String t, String top, int min, int max, List<T> src, List<T> dest) { return dest; }
    @Override public <T> List<T> getChoices(String m, int min, int max, Collection<T> c, Collection<T> s, FSerializableFunction<T, String> d) { return new ArrayList<>(s); }
    @Override public PaperCard chooseCard(String t, String m, List<PaperCard> l) { return l.isEmpty() ? null : l.get(0); }
    @Override public boolean isSupportedAudioFormat(File f) { return false; }
    @Override public IAudioClip createAudioClip(String f) { return null; }
    @Override public IAudioMusic createAudioMusic(String f) { return null; }
    @Override public void startAltSoundSystem(String f, boolean s) { }
    @Override public void showSpellShop() { }
    @Override public void showBazaar() { }
    @Override public IGuiGame getNewGuiGame() { return null; }
    @Override public HostedMatch hostMatch() { return null; }
    @Override public UpnpServiceConfiguration getUpnpPlatformService() { return null; }
    @Override public boolean hasNetGame() { return false; }
}
