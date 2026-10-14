import "./index.css";
import { Composition, Folder, Still } from "remotion";
import { Accroche } from "./scenes/Accroche";
import { Couverture } from "./scenes/Couverture";
import { Reel } from "./Reel";
import { Fin } from "./scenes/Fin";
import { Fonctions } from "./scenes/Fonctions";
import { Humeurs } from "./scenes/Humeurs";
import { StoryHumeurs, StoryLancement, StoryPermission, StorySalut, StoryYeux } from "./stories/Stories";
import { Pov } from "./scenes/Pov";
import { Planche } from "./scenes/Planche";
import { LinkedInFilm, LinkedInLancement, LinkedInPermission } from "./linkedin/LinkedIn";
import { MASTERCLASS_LENGTH, Masterclass } from "./linkedin/masterclass/Masterclass";
import { JOURNEE_LENGTH, Journee } from "./linkedin/journee/Journee";
import { JourneeEdito } from "./linkedin/journee/JourneeEdito";
import { ALPHA10_LENGTH, Alpha10 } from "./alpha10/Alpha10";
import { CAROUSEL_SLIDES, CarouselSlide } from "./carousel/Carousel";
import { Og } from "./demo/Og";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="Reel-Alpha10"
        component={Alpha10}
        durationInFrames={Math.round(ALPHA10_LENGTH * 60)}
        fps={60}
        width={1080}
        height={1920}
        defaultProps={{ lang: "fr" as const }}
      />
      <Composition
        id="Reel-Alpha10-EN"
        component={Alpha10}
        durationInFrames={Math.round(ALPHA10_LENGTH * 60)}
        fps={60}
        width={1080}
        height={1920}
        defaultProps={{ lang: "en" as const }}
      />
      <Folder name="Carrousel">
        {(["fr", "en"] as const).flatMap((lang) =>
          Array.from({ length: CAROUSEL_SLIDES }, (_, index) => (
            <Composition
              key={`${lang}-${index}`}
              id={`Carrousel-${lang}-${index + 1}`}
              component={CarouselSlide}
              durationInFrames={240}
              fps={60}
              width={1080}
              height={1350}
              defaultProps={{ lang, index }}
            />
          )),
        )}
      </Folder>
      <Composition
        id="Reel-Instagram"
        component={Reel}
        durationInFrames={1656}
        fps={60}
        width={1080}
        height={1920}
        defaultProps={{ accroche: "noir" }}
      />
      <Composition
        id="Reel-TikTok"
        component={Reel}
        durationInFrames={1656}
        fps={60}
        width={1080}
        height={1920}
        defaultProps={{ accroche: "pov" }}
      />
      <Still id="Couverture" component={Couverture} width={1080} height={1920} />
      <Folder name="Stories">
        <Composition id="Story1-Yeux" component={StoryYeux} durationInFrames={270} fps={60} width={1080} height={1920} />
        <Composition id="Story2-Lancement" component={StoryLancement} durationInFrames={300} fps={60} width={1080} height={1920} />
        <Composition id="Story3-Permission" component={StoryPermission} durationInFrames={255} fps={60} width={1080} height={1920} />
        <Composition id="Story4-Humeurs" component={StoryHumeurs} durationInFrames={360} fps={60} width={1080} height={1920} />
        <Composition id="Story5-Salut" component={StorySalut} durationInFrames={300} fps={60} width={1080} height={1920} />
      </Folder>
      <Folder name="LinkedIn">
        <Composition id="LinkedIn-Journee-4x5" component={Journee} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Journee-9x16" component={Journee} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="LinkedIn-Journee-Edito-4x5" component={JourneeEdito} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Journee-Edito-9x16" component={JourneeEdito} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Masterclass-16x9" component={Masterclass} durationInFrames={Math.round(MASTERCLASS_LENGTH * 60)} fps={60} width={1920} height={1080} />
        <Composition id="Masterclass-9x16" component={Masterclass} durationInFrames={Math.round(MASTERCLASS_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="LinkedIn-Film" component={LinkedInFilm} durationInFrames={1656} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Permission" component={LinkedInPermission} durationInFrames={255} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Lancement" component={LinkedInLancement} durationInFrames={300} fps={60} width={1080} height={1350} />
      </Folder>
      <Folder name="Plans">
        <Composition
          id="Accroche"
          component={Accroche}
          durationInFrames={300}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Pov"
          component={Pov}
          durationInFrames={300}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Fonctions"
          component={Fonctions}
          durationInFrames={954}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Humeurs"
          component={Humeurs}
          durationInFrames={204}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Fin"
          component={Fin}
          durationInFrames={198}
          fps={60}
          width={1080}
          height={1920}
        />
      </Folder>
      
      <Folder name="Social">
        <Still id="Og" component={Og} width={1200} height={630} />
      </Folder>
      <Folder name="Reference">
        <Composition
          id="Planche"
          component={Planche}
          durationInFrames={240}
          fps={30}
          width={1920}
          height={1080}
        />
      </Folder>
    </>
  );
};
